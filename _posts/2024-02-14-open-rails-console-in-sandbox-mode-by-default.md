---
layout: post
title: "rails consoleをdefaultでsandboxモードで起動する"
author: "@shouichi"
date: 2024-02-14 20:07:48 +09:00
tags: rails
---

バグの調査などのために本番環境で`rails console`を開く必要に迫られることはあります。このとき意図せずに本番データを書き換えてしまわないように注意が必要です。Railsは安全に見えるmethodでも副作用を伴う場合があります。例えば`has_one`で宣言したrelationに対して代入すると、即座にSQLが発行されます。

```ruby
class User < ApplicationRecord
  has_one :profile, dependent: :destroy
end

user = User.create(profile: Profile.new)
# INSERT INTO users;
# INSERT INTO profiles (user_id) VALUES (1);

user.profile = Profile.new
# DELETE FROM profiles WHERE id = 1;
# INSERT INTO profiles (user_id) VALUES (1);
```

このようなミスを防止するためには`rails console --sandbox`とsandboxモードで起動するのが良いでしょう。Sandboxモードで開いた`rails console`はtransactionで囲われており、consoleを終了した際に全てがrollbackされます。※データベースへの操作は全てrollbackされますが、それ以外（例えばredisへの書き込み）はrollbackされないことに注意しましょう。

TODO(shouichi): 該当のrailsコードを貼る。

ただし毎回`--sandbox`を指定するのは面倒ですし、指定を忘れかねません。こんな時に便利なのがRails 7.1で入った`sandbox_by_default`オプションです。[^1]

[^1]: [Add an option to start rails console in sandbox mode by default](https://github.com/rails/rails/pull/48984)

```ruby
module YourRailsApp
  class Application < Rails::Application
    config.sandbox_by_default = true
  end
end
```

これにより毎回オプションを指定しなくてもsandboxモードでconsoleが起動されます。データの書き換えが必要な場合は`rails console --no-sandbox`で起動します。

因みにこの機能はアニポスで毎回`--sandbox`を指定するのが面倒になり開発しました。Sandboxでconsoleを開く機能は以前からあったので実装自体は自明でした。加えた変更とそのテストは以下です。

```patch
     def sandbox?
-      options[:sandbox]
+      return options[:sandbox] if !options[:sandbox].nil?
+
+      return false if Rails.env.local?
+
+      app.config.sandbox_by_default
     end
```

この変更を送る際に`sandbox`オプションが正しく反映されているかのテストが書かれていることには感心しました。

```ruby
# https://github.com/rails/rails/blob/6e7ef7d61c7146ca03b173abc32f7ed97e3d949a/railties/test/application/console_test.rb
class ConsoleTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::Isolation

  def setup
    build_app
  end

  def teardown
    teardown_app
  end

  def test_sandbox_by_default
    add_to_config <<-RUBY
      config.sandbox_by_default = true
    RUBY

    options = "-e production -- --verbose"
    spawn_console(options)

    write_prompt "puts Rails.application.sandbox", "puts Rails.application.sandbox\r\ntrue"
    @primary.puts "quit"
  end
end
```

実際にrails applicationを起動して、その標準出力を比較することでテストを実現しています。すごい力技ですね。`build_app`と`teardown_app`の内容を以下に抜粋します。

```ruby
# https://github.com/rails/rails/blob/6e7ef7d61c7146ca03b173abc32f7ed97e3d949a/railties/test/isolation/abstract_unit.rb
module TestHelpers
  module Generation
    def build_app(options = {})
      FileUtils.rm_rf(app_path)
      FileUtils.cp_r(app_template_path, app_path)
    end

    def teardown_app
      FileUtils.rm_rf(tmp_path)
    end
end
```

抽象化をせずに直接テストしているところに、Active Recordに代表される「unit testよりintegration test重視」のRails精神が垣間見られました。
