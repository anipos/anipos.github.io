---
layout: post
title: "Active Storageの仕組み（その2）"
author: "@shouichi"
date: 2024-02-23 11:34:36 +09:00
tags: rails
---

前回[^1]に引き続きActive Storageの仕組みを見てみましょう。前回は`image_tag user.avatar`が、`ActiveStorage::Blobs::RedirectController#show`にroutingされることを突き止めました。今回はその中身を見ることから始めてみましょう。

[^1]: [Active Storageの仕組み（その1）]({% link _posts/2024-02-16-active-storage-internals-part-1.md %})

**※抜粋するRailsのコードは説明のために大幅に編集・簡略化してあります。**

```ruby
class ActiveStorage::Blobs::RedirectController < ActiveStorage::BaseController
  def show
    redirect_to @blob.url
  end
end
```

`ActiveStorage::Blob#url`でURLを生成し、そこにリダイレクトしています。

```ruby
class ActiveStorage::Blob < ActiveStorage::Record
  def url
    service.url key
  end
end
```

`ActiveStorage::Blob#service`を呼び出しているだけで、その実体は`ActiveStorage::Service::DiskService`です。

```ruby
irb> User.new.build_avatar_blob.service
=> #<ActiveStorage::Service::DiskService:0x00007fbe6e1eff58 @name=:local, @public=false>
```

```ruby
module ActiveStorage
  class Service::DiskService < Service
  end
end
```

さて、`ActiveStorage::Service::DiskService`のファイルを読んでも`#url`は見当たりません。困ったようですが、Rubyの`source_location`[^2]を使えば、定義ファイルと行を調べられます。

[^2]: [class Method - Documentation for Ruby 3.3](https://docs.ruby-lang.org/en/3.3/Method.html#method-i-source_location)

```ruby
irb> User.new.build_avatar_blob.service.method(:url).source_location
=> ["activestorage-7.1.3/lib/active_storage/service.rb", 119]
```

親クラスに定義されていました、その中身を確認してみましょう。

```ruby
module ActiveStorage
  class Service
    def url(key, **options)
      if public?
        public_url(key, **options)
      else
        private_url(key, **options)
      end
    end

    def public_url(key, **)
      raise NotImplementedError
    end

    def private_url(key, **)
      raise NotImplementedError
    end
  end
end
```

実装は子クラスにする想定のようです。`ActiveStorage::Service::DiskService`に戻りましょう。

```ruby
module ActiveStorage
  class Service::DiskService < Service
    def private_url(key, expires_in:)
      generate_url(key, expires_in: expires_in)
    end

    def public_url(key, filename:)
      generate_url(key, expires_in: nil)
    end

    def generate_url(key, expires_in:)
      verified_key_with_expiration = ActiveStorage.verifier.generate(
        {
          key: key,
        },
        expires_in: expires_in,
      )

      url_helpers.rails_disk_service_url(verified_key_with_expiration)
    end
  end
end
```

`private_url`と`public_url`の違いは有効期限の有無のみで、URLの生成は`generate_url`が担っています。`MessageVerifier`[^3]で`Blob#key`を署名、URL helperでURLを生成しています。

[^3]: [ActiveSupport::MessageVerifier](https://api.rubyonrails.org/classes/ActiveSupport/MessageVerifier.html)

`rails_disk_service_url`はActive Storageの`routes.rb`で定義されています。

```ruby
get  "/disk/:encoded_key/*filename" => "active_storage/disk#show",
  as: :rails_disk_service
```

Routing先のcontrollerを見てみましょう。

```ruby
class ActiveStorage::DiskController < ActiveStorage::BaseController
  def show
    if key = decode_verified_key
      serve_file named_disk_service(key[:service_name]).path_for(key[:key]))
    else
      head :not_found
    end
  end

  private
    def named_disk_service(name)
      ActiveStorage::Blob.services.fetch(name) do
        ActiveStorage::Blob.service
      end
    end

    def decode_verified_key
      key = ActiveStorage.verifier.verified(params[:encoded_key])
      key&.deep_symbolize_keys
    end

    def serve_file(path)
      Rack::Files.new(nil).serving(request, path).tap do |(status, headers, body)|
        self.status = status
        self.response_body = body

        headers.each do |name, value|
          response.headers[name] = value
        end
      end
    end
end
```

`MessageVerifier`で署名した`Blob#key`を取り出し、`DiskService#path_for`で対応するファイルのパスを得ています。実際にファイルを送る処理は`Rack::Files`に委譲しています。

```ruby
module ActiveStorage
  class Service::DiskService < Service
    def path_for(key)
      File.join root, folder_for(key), key
    end

    def folder_for(key)
      [ key[0..1], key[2..3] ].join("/")
    end
  end
end
```

ファイルのパスを返しているだけですが、フォルダを階層化している点は注目に値します。これは1つのフォルダに置けるファイル数の上限と、パフォーマンスのためと思われます[^4]（GitHub[^5][^6]に背景が書いておらず、はっきりとした理由は不明です）。

[^4]: [How many files can I put in a directory?](https://stackoverflow.com/questions/466521/how-many-files-can-i-put-in-a-directory)
[^5]: [Add Active Storage to Rails](https://github.com/rails/rails/pull/30019)
[^6]: [Add Active Storage to Rails](https://github.com/rails/rails/pull/30020)

これにてActive Storageがファイルを返すまでの動きを理解することが出来ました。
