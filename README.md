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

## 導入手順

### 1. Gemfile に追加

Rails アプリの `Gemfile` に `devise` とこの gem を追加します。

```ruby
gem "devise"
gem "devise_ldap_multidomain_authenticatable"
```

install されていなければ bundle install します。

```bash
bundle install
```

### 2. Devise を install

まだ Devise を入れていないアプリでは、まず Devise の generator を実行します。

```bash
bin/rails generate devise:install
```

必要に応じて、アプリの `User` モデルも作成します。

```bash
bin/rails generate devise User
```

すでに `User` モデルがある場合は、この step は不要です。

### 3. この gem の generator を実行

LDAP multi-domain 用の initializer、設定ファイル、migration を生成します。

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

### 4. migration を実行

```bash
bin/rails db:migrate
```

### 5. `devise.rb` を設定

この gem は、Devise 側の認証キーが `emp_id` であることを想定しています。

`config/initializers/devise.rb` に次の設定を入れてください。

```ruby
Devise.setup do |config|
  config.authentication_keys = [:emp_id]
end
```

`case_insensitive_keys` や `strip_whitespace_keys` も `email` 前提になっているなら、必要に応じて `emp_id` に寄せてください。

```ruby
Devise.setup do |config|
  config.authentication_keys = [:emp_id]
  config.case_insensitive_keys = [:emp_id]
  config.strip_whitespace_keys = [:emp_id]
end
```

### 6. User モデルへ module を追加

`User` モデルで `:ldap_multidomain_authenticatable` を有効にします。

```ruby
class User < ApplicationRecord
  devise :ldap_multidomain_authenticatable, :rememberable, :trackable

  def self.find_for_ldap_multidomain_authentication(auth_result, authentication_hash)
    find_by(emp_id: auth_result.emp_id)
  end
end
```

既存アプリで `database_authenticatable` を使っている場合は、この gem で LDAP 認証に切り替えるなら `:ldap_multidomain_authenticatable` へ置き換えてください。

### 7. ログインフォームを `emp_id` ベースにする

Devise の sign in form でも、ユーザーに入力してもらう識別子は `email` ではなく `emp_id` にします。

例えば `app/views/devise/sessions/new.html.erb` では次のような形です。

```erb
<%= f.label :emp_id %>
<%= f.text_field :emp_id, autofocus: true %>

<%= f.label :password %>
<%= f.password_field :password, autocomplete: "current-password" %>
```

### 8. `config/ldap_multidomain.yml` を設定

各 AD / LDAP ドメインの bind 方法を設定します。

設定例:

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

389 ポートで通常 LDAP を使うなら `port: 389` を指定し、`simple_tls` は外してください。389 + StartTLS を使うなら `encryption: start_tls` を指定します。

```yaml
production:
  domains:
    - key: primary
      host: dc1.example.local
      port: 389
      base: dc=example,dc=local
      auth_format: "%{login}@example.local"
      encryption: start_tls
```

### 9. 動作確認

アプリを起動して、Devise の sign in 画面から `emp_id` と `password` でログインできることを確認します。

```bash
bin/rails server
```

確認ポイントは次の通りです。

- `emp_id` 入力でログインできる
- LDAP bind が成功したドメインで認証される
- `users.emp_id` に 5 桁で保存される
- `users.last_authenticated_domain` に成功ドメインが保存される

### 10. 既存の `database_authenticatable` から切り替えるときの注意

- アプリ側の sign in フォームが `email` 前提のままだとログインできません
- `config.authentication_keys` が `[:email]` のままだと strategy が期待通り動きません
- LDAP 認証へ完全に切り替えるなら、`User` の devise modules から `:database_authenticatable` を外す運用を想定しています
- 既存パスワードログインと併用したい場合は、アプリ側の認証フロー設計を別途検討してください

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
