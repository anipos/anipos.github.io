---
layout: post
title: "Active Recordのscopeに対してclass methodが呼べる理由"
author: "@shouichi"
tags: rails
---

皆さんはscopeとclass methodが組み合わせ可能なことを不思議に思ったことはありませんか。

```ruby
class User < ApplicationRecord
  scope :active, -> { where.not(activated_at: nil) }

  def self.name_starts_with(prefix)
    where("name LIKE ?", "#{prefix}%")
  end
end

User.active.name_starts_with("a")
#=> [#<User:0x000072dcf11a4398>, ....]
```

結論から書くと、`scope`は内部的にclass methodを定義しているからです。誤解を恐れずに言うと、`scope`とclass methodはほぼ同値です。

では内部を探っていきましょう。先ずは`scope`の定義場所を調べます。

```ruby
User.method(:scope).source_location
=> ["activerecord-7.1.3.2/lib/active_record/scoping/named.rb", 154]
```

```ruby
# https://github.com/rails/rails/blob/84c4598c93f04d00383e5e27cdffd65fb31ae5e7/activerecord/lib/active_record/scoping/named.rb
module ActiveRecord
  module Scoping
    module Named
      module ClassMethods
        def scope(name, body, &block)
          extension = Module.new(&block) if block

          if body.respond_to?(:to_proc)
            singleton_class.define_method(name) do |*args|
              scope = all._exec_scope(*args, &body)
              scope = scope.extending(extension) if extension
              scope
            end
          else
            singleton_class.define_method(name) do |*args|
              scope = body.call(*args) || all
              scope = scope.extending(extension) if extension
              scope
            end
          end
          singleton_class.send(:ruby2_keywords, name)

          generate_relation_method(name)
        end
      end
    end
  end
end
```

`singleton_class.define_method`でclass methodを定義しています。`has_many`と同様にextensionを渡せるのは面白いですね。
