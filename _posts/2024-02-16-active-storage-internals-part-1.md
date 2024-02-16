---
layout: post
title: "Active Storageの仕組み（その１）"
author: "@shouichi"
date: 2024-02-16 19:35:57 +09:00
tags: rails
---

今回から何回かに分けてActive Storage[^1]の仕組みを紐解いてみましょう。 さて、早速ですが公式ガイドにならい`User`が`avatar`を持っているとします。

[^1]: [Active Storage Overview](https://edgeguides.rubyonrails.org/active_storage_overview.html)

```ruby
class User < ApplicationRecord
  has_one_attached :avatar
end
```

`avatar`を表示するには`image_tag`に`user.avatar`を渡すだけです。

```erb
<%= image_tag user.avatar %>
```

すると以下のようなリンクが生成されます。

```html
<img
  src="/rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsiZGF0YSI6MSwicHVyIjoiYmxvYl9pZCJ9fQ==--22989801b78c27abf7bc8c8b023cac322a42fbea/dog.jpg"
/>
```

ここで連鎖的に疑問が生まれます。

1. `user.avatar`を渡すと`/rails/active_storage/blob/redirect/...`なるURLが生成されたのは何故か。
1. Railsの規約に従うなら`/avatars/1`のようなURLが生成されるべきではないのか。
1. そもそも`user.avatar`とは何か。

順番に調べてみましょう。まずは`user.avatar`の実態は何かを調べます。

```ruby
irb> User.first.avatar
#<ActiveStorage::Attached::One:0x00007ff680e052a8
 @name="avatar",
 @record=
  #<User:0x00007ff68104ab58>
```

`ActiveStorage::Attached::One`が返却されました。

**※以下より後に抜粋するRailsのコードは説明のために大幅に編集・簡略化してあります。**

```ruby
module ActiveStorage
  class Attached
  end

  class Attached::One < Attached
  end
end
```

どうやら`ActiveStorage::Attached::One`はPORO（Plain Old Ruby Object）のようです。言い換えるとActive Recordを継承している訳ではないので、`link_to`や`image_tag`に渡すとエラーになりそうなものです。実際にPOROを`link_to`に渡すと以下のエラーが発生します。

```ruby
class Post # ApplicationRecordから継承してないことに注意。
end
```

```erb
<%= link_to "Post", Post.new %>
#=> undefined method `to_model' for #<Post:0x00007fe354a9aeb8>
```

ではPOROであるにも関わらず`ActiveStorage::Attached::One`がエラーにならないのは何故でしょうか。中身をもう少し掘り下げてみましょう。

```ruby
module ActiveStorage
  class Attached::One < Attached
    delegate_missing_to :attachment
  end
end
```

どうやら`delegate_missing_to`大体の処理を`attachment`に移譲しているようです。そこで`attachment`の正体を探ってみましょう。

```ruby
irb> User.first.avatar.attachment
=> #<ActiveStorage::Attachment:0x00007f8f12b568e8 id: 1, name: "avatar", record_type: "User", record_id: 1, blob_id: 1>
```

`attachment`の正体は`ActiveStorage::Attachment`だと分かりました。これの実装を確認してみましょう。

```ruby
class ActiveStorage::Attachment < ActiveStorage::Record
end

class ActiveStorage::Record < ActiveRecord::Base
  self.abstract_class = true
end
```

`ActiveRecord::Attachment`は`ActiveRecord::Base`を継承していました。本丸に近付いて来たようですが、やはり生成されるURLがRailsの規約に従っておらず、疑問が残ります。

```html
<!-- 実際に生成されたURL -->
<img
  src="/rails/active_storage/blobs/redirect/eyJfcmFpbHMiOnsiZGF0YSI6MSwicHVyIjoiYmxvYl9pZCJ9fQ==--22989801b78c27abf7bc8c8b023cac322a42fbea/dog.jpg"
/>

<!-- Railsの規約に従えば生成されるであろうURL -->
<img src="/active_storage/attachments/1" />
```

さて、最後の鍵はActive Storageの`routes.rb`にあります。

```ruby
resolve("ActiveStorage::Attachment") do |attachment, options|
  route_for(:rails_storage_redirect, attachment.blob, options)
end
```

上記により`link_to`などに`ActiveStorage::ActiveStorage`が渡された場合、`rails_storage_redirect`を呼び出すようにしています。これがRailsの規約ではないURLが生成されていた理由です。では次に`rails_storage_redirect`の中身を見ましょう。

```ruby
direct :rails_storage_redirect do |model, options|
  route_for(:rails_service_blob, model.signed_id)
end
```

これも`rails_service_blob`を呼び出しているだけですが、注目すべき点が1つあります。それは呼び出しの際に`model.signed_id`[^2]を呼び出している点です。これが生成されたURLにランダムな文字列が含まれていた理由です。実際に`signed_id`を呼び出してみると、URLの文字列と一致してることが分かります。

```ruby
irb> User.first.avatar.attachment.blob.signed_id
#=> "eyJfcmFpbHMiOnsiZGF0YSI6MSwicHVyIjoiYmxvYl9pZCJ9fQ==--22989801b78c27abf7bc8c8b023cac322a42fbea"
```

[^2]: [ActiveRecord::SignedId](https://api.rubyonrails.org/classes/ActiveRecord/SignedId.html#method-i-signed_id)

最後に`rails_service_blob`ですが、これは`ActiveStorage::Blobs::RedirectController#show`を呼び出しているだけです。この部分の記法は馴染み深いでしょう。

```ruby
get "/blobs/redirect/:signed_id/*filename" => "active_storage/blobs/redirect#show", as: :rails_service_blob
```

さて、これにて`user.avatar`からURLが生成される仕組みを解明出来ました。`routes.rb`で使用されていた`resolve`や`direct`は、日常的に使うものではありませんが、Active Storageではその仕組みを上手に使ってURLを生成していることが分かりました。Railsのroutingは上手に設定すると非常に便利です。改めて公式ガイド[^3]を読むことをお勧めします。

[^3]: [Rails Routing from the Outside In](https://guides.rubyonrails.org/routing.html)

長くなってしまったので今回はここまでとします。次回は`ActiveStorage::Blobs::RedirectController#show`の中身から続きを確認しましょう。
