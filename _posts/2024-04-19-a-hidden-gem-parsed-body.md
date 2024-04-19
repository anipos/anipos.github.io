---
layout: post
title: "テストではJSON.parseの変わりにparsed_bodyを使いましょう"
author: "@shouichi"
date: 2024-04-19 16:27:46 +09:00
tags: rails
---

APIのテストをする際に手で`JSON.parse`を呼んでいる人は多いでしょう。もちろんそれで問題がある訳ではないですが、実は`ActionDispatch::TestResponse#parsed_body`を呼び出せばMIME typeに応じてbodyをparseしてくれます。

```ruby
get posts_path
response.content_type                  #=> "text/html; charset=utf-8"
response.parsed_body                   #=> Nokogiri::HTML5::Document
response.parsed_body.at_css("#posts")  #=> #<Nokogiri::XML::Element:0xea24...

get posts_path, as: :json
response.content_type #=> "application/json; charset=utf-8"
response.parsed_body  #=> Array
response.parsed_body  #=> [{"id"=>42, "title"=>"Title"},...

get post_path(post), as: :json
response.content_type #=> "application/json; charset=utf-8"
response.parsed_body  #=> Hash
response.parsed_body  #=> {"id"=>42, "title"=>"Title"}
```

Railsはdefaultでhtml/jsonに対応しています。

```ruby
# https://github.com/rails/rails/blob/cc638d1c09f11ac1307ad887d5bb9e41d6be3aa5/actionpack/lib/action_dispatch/testing/request_encoder.rb#L57-L58
module ActionDispatch
  class RequestEncoder # :nodoc:
    register_encoder :html,
      response_parser: -> body { Rails::Dom::Testing.html_document.parse(body) }
    register_encoder :json,
      response_parser: -> body { JSON.parse(body, object_class: ActiveSupport::HashWithIndifferentAccess) }
  end
end
```

自分で別のformatを追加する事も出来ます。例えばxmlを追加してみましょう。

```ruby
ActionDispatch::IntegrationTest.register_encoder :xml,
  response_parser: -> body { REXML::Document.new(body) }

get posts_path, as: :xml
response.content_type                                  #=> "application/xml; charset=utf-8"
response.parsed_body                                   #=> REXML::Document
response.parsed_body.elements["posts/post[1]/id"].text #=> "42"
```

Railsはこの様にちょっと気の利いた機能があり、かつそれが拡張可能になっていて良いですね。
