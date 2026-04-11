# devise_ldap_multidomain_authenticatable

`devise_ldap_multidomain_authenticatable` は、Rails アプリで Devise のログイン体験を維持したまま、LDAP 認証部分だけを複数ドメイン対応の direct bind に差し替えるための gem です。

## 何を解決するか

- `authenticate_user!`、session 管理、`rememberable`、`trackable`、failure handling をそのまま使えます。
- 複数の Active Directory / LDAP ドメインに対して認証できます。
- ユーザー入力は `emp_id` と `password` に寄せて運用できます。
- `sAMAccountName` の入力揺れをロジック側で吸収できます。
- 前回認証に成功したドメインを `User` に記録し、次回はそのドメインを最初に試します。
- 前回のドメインで失敗した場合は、残りのドメインに対して並列認証へフォールバックします。
- bind 用の admin / service account は不要です。
- `User.emp_id` に社員番号を 5 桁で補完できます。

## 何を解決しないか

- LDAP 検索や DN 解決
- LDAP 属性同期
- グループ所属判定
- パスワード変更
- search + bind 方式

## `devise_ldap_authenticatable` との違い

この gem は direct bind 専用です。LDAP 検索を前提にせず、サービスアカウントも使いません。各ドメイン設定の `auth_format` から bind username を組み立て、`Net::LDAP#bind` を直接試します。

## インストール

Rails アプリの `Gemfile` に追加します。

```ruby
gem "devise_ldap_multidomain_authenticatable"
```

設定ファイルを生成します。

```bash
bin/rails generate devise_ldap_multidomain_authenticatable:install
```

この generator は以下をまとめて作成します。

- `config/initializers/devise_ldap_multidomain_authenticatable.rb`
- `config/ldap_multidomain.yml`
- `emp_id` と前回成功ドメイン保存用の migration

テーブル名や属性名を変えたい場合は option を使えます。

```bash
bin/rails generate devise_ldap_multidomain_authenticatable:install \
  --model_name members \
  --remembered_domain_attribute ldap_domain_key
```

## 設定

`config/ldap_multidomain.yml` を作成します。

```yaml
common: &common
  port: 636
  encryption: simple_tls
  connect_timeout: 1
  read_timeout: 2

production:
  parallel: true
  stop_on_first_success: true
  max_parallelism: 2
  overall_timeout: 3
  remembered_domain_attribute: last_authenticated_domain
  emp_id_attribute: emp_id
  domains:
    - key: domain_a
      host: dc1.domain-a.local
      base: dc=domain-a,dc=local
      auth_format: "%{login}@domain-a.local"
      <<: *common

    - key: domain_b
      host: dc1.domain-b.local
      base: dc=domain-b,dc=local
      auth_format: "DOMAINB\\%{login}"
      <<: *common
```

Railtie により、このファイルは Rails 起動時に自動で読み込まれます。

## User モデルへの組み込み

```ruby
class User < ApplicationRecord
  devise :ldap_multidomain_authenticatable, :rememberable, :trackable

  def self.find_for_ldap_multidomain_authentication(auth_result, authentication_hash)
    find_by(emp_id: auth_result.emp_id)
  end
end
```

Devise 側は `emp_id` を認証キーにする想定です。

```ruby
# config/initializers/devise.rb
config.authentication_keys = [:emp_id]
```

## `sAMAccountName` の揺れ吸収

この gem では、入力された `emp_id` から bind 用の `sAMAccountName` と 5 桁の `emp_id` を正規化します。

想定している入力揺れ:

- `d1234`
- `1234`
- `d01234`
- `01234`
- `12345`
- `d12345`

正規化の例:

- `1234` -> bind 用 `sAMAccountName`: `d1234` / `emp_id`: `01234`
- `d1234` -> bind 用 `sAMAccountName`: `d1234` / `emp_id`: `01234`
- `01234` -> bind 用 `sAMAccountName`: `d1234` / `emp_id`: `01234`
- `d01234` -> bind 用 `sAMAccountName`: `d1234` / `emp_id`: `01234`
- `12345` -> bind 用 `sAMAccountName`: `d12345` / `emp_id`: `12345`

LDAP には候補をいろいろ試すのではなく、正規化した `sAMAccountName` を 1 つだけ使って bind します。つまり `01234` や `d01234` と入力されても、AD には `d1234` として bind します。

フォーム入力は `emp_id` でも、`auth_format` の `%{login}` には正規化後の bind 用値が入ります。

```yaml
auth_format: "%{login}@domain-a.local"
```

この例では、ユーザーが `emp_id=01234` と入力すると、実際の bind username は `d1234@domain-a.local` になります。

## `emp_id` と前回成功ドメインの記録

デフォルトでは `emp_id` と `last_authenticated_domain` を使います。install generator を実行すると migration も自動生成されますが、手で追加するなら以下です。

```ruby
add_column :users, :emp_id, :string
add_index :users, :emp_id
add_column :users, :last_authenticated_domain, :string
add_index :users, :last_authenticated_domain
```

認証成功後は次の情報を補完します。

- `emp_id` があれば 5 桁で保存
- `last_authenticated_domain` があれば成功ドメインを保存

次回認証時には、そのドメインと一致するドメインをまず単独で試し、失敗したときだけ残りのドメインを並列に試します。

属性名を変えたい場合は `remembered_domain_attribute` と `emp_id_attribute` を設定してください。

```yaml
production:
  emp_id_attribute: employee_code
  remembered_domain_attribute: ldap_domain_key
```

モデル側で独自制御したい場合は、以下の hook を使えます。

```ruby
class User < ApplicationRecord
  def last_authenticated_ldap_domain
    preferred_ldap_domain
  end

  def remember_ldap_multidomain_authentication!(auth_result)
    update!(
      preferred_ldap_domain: auth_result.domain_key,
      emp_id: auth_result.emp_id
    )
  end
end
```

## direct bind の流れ

各ドメインは `auth_format` から bind username を組み立てます。

- `"%{login}@domain-a.local"`
- `"DOMAINA\\%{login}"`

認証時の流れは次の通りです。

1. 入力された `emp_id` から bind 用の `sAMAccountName` と 5 桁の `emp_id` を正規化します。
2. `emp_id` や custom hook を使って既存 `User` を解決できる場合は、前回成功ドメインを取得します。
3. 前回成功ドメインがあれば、そのドメインだけを先に試します。
4. 失敗した場合は、残りのドメインに対して parallel 認証を行います。
5. 最初に成功したドメインの結果で Devise の sign in に進みます。
6. 認証成功後に `emp_id` と成功ドメインを `User` へ補完します。

## 並列認証の注意点

- `parallel` のデフォルトは `true`
- `stop_on_first_success` のデフォルトは `true`
- `max_parallelism` のデフォルトは `domains.size`
- `overall_timeout` で全体の待ち時間上限を設定できます

アカウントロックが厳しい環境では、無効なパスワードが複数ドメインに対して試行される点に注意してください。前回成功ドメインの優先試行は、このリスクと待ち時間を少し下げるための仕組みでもあります。

## セキュリティ上の注意

- `password` はログに出しません。
- `bind_username` は `mask_bind_username_in_logs` でマスクできます。
- まずは private gem / path gem として使い、運用条件に合うことを確認してから展開するのがおすすめです。

## テスト

このプロジェクトは RSpec を使い、実 LDAP には接続せず `Net::LDAP` を stub して検証します。

```bash
bundle exec rspec
```
