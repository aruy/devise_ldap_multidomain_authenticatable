# Codex向け実装指示書: devise_ldap_multidomain_authenticatable

## 目的

Rails アプリで **Devise を継続利用**しつつ、LDAP 認証部分だけを差し替える。

既存の `devise_ldap_authenticatable` のような「検索 + bind ユーザー」方式ではなく、以下の要件を満たす **direct bind 専用の Devise 拡張 gem** を実装したい。

- 複数 Active Directory / LDAP ドメインを対象にする
- 各ドメインに対して **bind 用サービスアカウントを持たない**
- ユーザー入力の `login` と `password` を使って **本人資格情報で direct bind** する
- 複数ドメインへは **並列で同時に bind 試行**する
- **どれか 1 ドメインで認証成功した時点でログイン成功** とする
- Devise の `authenticate_user!`、session 管理、failure handling などはそのまま活かす

---

## 実装したい gem 名

第一候補:

- `devise_ldap_multidomain_authenticatable`

必要に応じて module 名 / namespace 名もこれに合わせること。

---

## 重要な前提

### 認証方式

この gem は **LDAP 検索ベースではなく direct bind ベース** とする。

つまり以下は **やらない**。

- bind 用 admin / service account で LDAP 検索
- DN 検索後に再 bind
- グループ検索
- LDAP 属性同期
- LDAP 上のメールアドレス / 表示名 / 部署取得

この gem で最初に解決したい問題は **認証のみ**。

### 入力として使うもの

アプリから受け取るユーザー認証情報は以下。

- `login` （実質 `sAMAccountName` を想定）
- `password`

ドメイン設定ごとに、bind に使うユーザー名を組み立てる。

例:

- `"%{login}@domain-a.local"`
- `"DOMAINA\\%{login}"`

---

## 実装ゴール

Rails アプリ側で最終的にこう書けるようにしたい。

```ruby
class User < ApplicationRecord
  devise :ldap_multidomain_authenticatable, :rememberable, :trackable
end
```

Devise のログインフォームから通常通りサインインできること。

---

## 採用したい技術方針

### 1. Devise custom module + custom Warden strategy

Devise のカスタム module と Warden strategy を使って認証を実装すること。

想定:

- `Devise.add_module :ldap_multidomain_authenticatable, ...`
- `Devise::Strategies::LdapMultidomainAuthenticatable < Devise::Strategies::Authenticatable`
- `Warden::Strategies.add(:ldap_multidomain_authenticatable, ...)`

### 2. LDAP 通信は net-ldap

LDAP 接続・bind には `net-ldap` を使うこと。

検索ベースの `bind_as` ではなく、基本は `Net::LDAP.new(...).bind` を使うこと。

### 3. LDAP認証本体は service object に分離

Warden strategy 内に LDAP 接続処理をベタ書きしないこと。

例:

- `DeviseLdapMultidomainAuthenticatable::Authenticator`
- `DeviseLdapMultidomainAuthenticatable::ParallelAuthenticator`
- `DeviseLdapMultidomainAuthenticatable::DomainConfig`

---

## 必須要件

### 要件1: 複数ドメイン direct bind

設定された複数ドメインに対して認証を試行する。

ドメインごとの設定値として、最低限以下を持てるようにすること。

- `key`
- `host`
- `port`
- `base`（現時点では未使用でも保持可）
- `auth_format`
- `encryption`
- `connect_timeout`
- `read_timeout`（使える形なら）
- `tls_options`（必要なら）

### 要件2: 並列実行

ドメイン試行は逐次ではなく **並列** で行うこと。

想定方式:

- Ruby `Thread`
- `Queue` を使って成功結果を親スレッドへ返す
- どこか 1 スレッドが成功したらその結果を採用
- 他スレッドは短時間で join するか、必要なら停止

注意:

- 実装は「認証成功を最速で返す」が主目的
- 他スレッドの完全即時停止にはこだわらず、安全性を優先する
- スレッド例外で全体が落ちないようにする

### 要件3: 最初の成功を採用

- 1 ドメインでも bind 成功したら認証成功
- 成功したドメイン情報を result に含めること
- 全ドメイン失敗なら認証失敗

### 要件4: User の解決

認証成功後は、アプリ側の `User` を解決する必要がある。

初期実装では以下のどちらかを選べるようにしたい。

#### パターンA: 既存ユーザーのみ許可

- `find_for_authentication(login: ...)` 相当で既存ユーザーを探す
- 見つからなければ失敗

#### パターンB: 自動作成許可

- 設定で有効な場合は、最小限の属性で `User` を新規作成
- 初期は `login` または `emp_id` 相当のキーだけ保持できればよい

まずは **A をデフォルト** にすること。

### 要件5: Deviseとの自然な統合

- `authenticate_user!` で使える
- 通常の Devise ログイン画面から利用可能
- Devise failure message を使う
- rememberable / trackable 等の既存モジュールと共存できる

---

## 設定ファイル仕様

`config/ldap_multidomain.yml` を使いたい。

例:

```yaml
common: &common
  port: 636
  encryption: simple_tls
  connect_timeout: 1
  read_timeout: 2

production:
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

### 設定読み込み要件

- Rails 起動時に読み込めること
- 環境別 (`development`, `test`, `production`) に切り替わること
- ERB を使えるようにしてもよい
- 不正な設定時は明確に例外を出すこと

---

## gem の想定構成

```ruby
lib/
  devise_ldap_multidomain_authenticatable.rb
  devise_ldap_multidomain_authenticatable/version.rb
  devise_ldap_multidomain_authenticatable/railtie.rb
  devise_ldap_multidomain_authenticatable/config.rb
  devise_ldap_multidomain_authenticatable/result.rb
  devise_ldap_multidomain_authenticatable/domain_config.rb
  devise_ldap_multidomain_authenticatable/authenticator.rb
  devise_ldap_multidomain_authenticatable/parallel_authenticator.rb
  devise/models/ldap_multidomain_authenticatable.rb
  devise/strategies/ldap_multidomain_authenticatable.rb
```

必要なら generator も追加すること。

例:

- `rails generate devise_ldap_multidomain_authenticatable:install`

生成物候補:

- initializer
- `config/ldap_multidomain.yml`

---

## 実装詳細要件

### 1. Result オブジェクト

認証結果は値オブジェクトで返してほしい。

最低限ほしい値:

- `success?`
- `domain_key`
- `bind_username`
- `login`
- `error`
- `exception_class`（あれば）
- `exception_message`（あれば）

### 2. ログ

本番運用を考え、ログは最低限出したい。

ログ要件:

- どのドメインへ試行したか
- 成功したドメインはどこか
- 失敗したドメインはどこか
- 例外が出た場合はクラス名とメッセージ

ただし注意:

- **password は絶対にログへ出さないこと**
- `bind_username` は出してもよいが、設定でマスク可能だと望ましい

### 3. timeout

LDAP サーバの応答待ちでログインが過度に遅くならないようにしたい。

要件:

- ドメインごとの `connect_timeout`
- 必要なら全体タイムアウト
- タイムアウト時にそのドメイン失敗として扱う

### 4. スレッド安全性

- クラス変数で mutable state を持たないこと
- 1 リクエスト中の認証処理が他リクエストと干渉しないこと
- `Thread.abort_on_exception` に依存しないこと

### 5. Ruby / Rails 対応

少なくとも以下を意識すること。

- Ruby 3.x
- Rails 7.x / 8.x
- Devise 最新安定系を想定

---

## User 解決の設計方針

この gem は LDAP 認証成功後、アプリ側 resource をどう見つけるかの拡張ポイントを持つこと。

### 必須

モデル側で override 可能にしたい。

例えば `User` 側で以下のような hook を持てるとよい。

```ruby
class User < ApplicationRecord
  devise :ldap_multidomain_authenticatable

  def self.find_for_ldap_multidomain_authentication(auth_result, authentication_hash)
    find_by(login: auth_result.login)
  end
end
```

### fallback

この hook が未実装なら、Devise の authentication key を使って素直に検索してよい。

---

## 並列認証の期待挙動

### 成功時

- 全ドメインへ並列試行開始
- 最初に成功した 1 件を採用
- すぐに Devise の `success!` へ進む
- 他スレッドは短時間で join、または安全に終了させる

### 失敗時

- すべて失敗なら `fail!(:invalid)` 相当
- 接続例外や timeout も失敗として集約

### 注意

アカウントロックポリシーが厳しい環境では、「複数ドメインへ同時失敗」が問題になり得る。
そのため、以下も設定可能だと望ましい。

- `parallel: true/false`
- `max_parallelism`
- `stop_on_first_success`

初期値は以下を希望。

- `parallel: true`
- `stop_on_first_success: true`
- `max_parallelism: domains.size`

---

## ほしいAPIイメージ

```ruby
result = DeviseLdapMultidomainAuthenticatable::ParallelAuthenticator.call(
  login: "nakajima",
  password: "secret",
  domains: configured_domains,
  logger: Rails.logger
)

result.success?      # => true / false
result.domain_key    # => "domain_a"
result.bind_username # => "nakajima@domain-a.local"
```

---

## テスト要件

RSpec 想定でテストを用意すること。

### 単体テスト

- auth_format で bind username を正しく組み立てる
- 1 ドメイン成功時に success result を返す
- 複数ドメインのうち 1 件成功で success になる
- 全件失敗で failure になる
- timeout を failure として処理する
- 例外発生時も全体が落ちず failure 扱いになる

### strategy テスト

- Devise login で custom strategy が使われる
- 認証成功時に resource が sign in される
- 認証失敗時に failure message が返る

### integration / dummy app テスト

可能なら dummy Rails app を用意し、以下を確認する。

- `devise :ldap_multidomain_authenticatable` が有効になる
- ログイン画面から認証できる
- initializer / yml 読み込みが動く

### テスト実装上の注意

- 実 LDAP は使わず stub / fake でテストする
- `Net::LDAP` を差し替え可能な構造にする
- 並列処理テストは flaky になりやすいので工夫する

---

## 実装時の非要件

初期版では以下は不要。

- LDAP 属性同期
- LDAP グループ所属判定
- パスワード変更
- bind ユーザー対応
- DN 検索
- 複雑な failover retry
- connection pool
- metrics 送信

まずは **認証専用** で完成させること。

---

## Codexへの実装方針のお願い

以下の順で実装してほしい。

1. gem 雛形作成
2. Devise module 登録
3. Warden strategy 実装
4. 設定 loader 実装
5. direct bind authenticator 実装
6. parallel authenticator 実装
7. resource 解決 hook 実装
8. installer generator 実装
9. RSpec テスト追加
10. README 作成

---

## README に含めてほしい内容

- gem の目的
- 何を解決し、何を解決しないか
- `devise_ldap_authenticatable` との違い
- インストール手順
- initializer / yml 設定例
- User モデルへの組み込み例
- ログイン項目が `email` ではなく `login` の場合の例
- 並列認証の注意点
- セキュリティ上の注意点
- テスト方法

---

## 受け入れ条件

以下を満たせば初期完成とみなす。

- Rails アプリに組み込める
- Devise のログインで custom strategy が動く
- `config/ldap_multidomain.yml` を読める
- 複数ドメインへ direct bind を並列実行できる
- 1 件成功でログイン成功になる
- bind ユーザー不要
- 最低限のテストが通る
- README で利用方法が分かる

---

## 参考方針

- Devise custom module / strategy を使う
- Warden strategy の `authenticate!` / `valid?` を正しく実装する
- LDAP は `net-ldap` の direct bind を使う
- 認証部分は service object として分離する
- 将来拡張しやすいが、初版は認証のみに絞る

---

## 実装上の補足メモ

- 既存の `devise_ldap_authenticatable` は検索寄りの思想なので、その fork より新規で薄く作る方が望ましい
- `sAMAccountName` をログインIDとして使うことを想定しているが、内部 bind username は `auth_format` で自由に組み立てられるようにする
- 複数ドメインに対して同時失敗が発生し得るため、アカウントロックポリシーには注意喚起を入れる
- 実装は private gem / path gem としてまず使える形でよい

