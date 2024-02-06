---
layout: post
title: "CSVエクスポート機能でもレールに乗る"
author: "@shouichi"
date: 2024-02-05 21:05:31 +09:00
categories: rails
---

データのCSV形式エクスポート機能はあらゆるアプリケーションで求められる事でしょう。Controllerで直接CSVを作りそれを送るのが素朴な実装で、それで問題なく動作する場合も多いでしょう。

```ruby
class Admin::UsersController < ApplicationController
  def index
    @users = User.search(conditions)

    respond_to.csv |format|
      format.html
      format.csv { send_file(generate_csv(@users)) }
    end
  end
end
```

ただしこの実装は潜在的に以下の問題をはらんでいます。

- Web serverのworkerを長い時間占有する。
- 処理時間が一定以上長くなるとタイムアウトする。

これらの問題に対処するためにはCSV処理をbackground workerに任せるのが良いでしょう。

```ruby
class Admin::UserExportJob
  def perform(conditions)
    csv = generate_csv(User.search(conditions))
    bucket.create_file(csv)
  end

  private

  def bucket
    @bucket = storage.bucket("my-bucket")
  end

  def storage
    @storage ||= Google::Cloud::Storage.new(
      project_id: "my-project",
      credentials: "/path/to/keyfile.json"
    )
  end
end
```

一方で上記の実装にもいくつかの問題があります。

- GCSとの通信を直書きしているのでテストが書き難い。
- Active Storageを使っている場合にbucketの設定が重複している。

もちろんWebMockなどを使えばこれもテスト可能でしょう。[^1]ただしレールに乗っている感がありません。Active Storageを使ってもっとレールに乗れないでしょうか。

[^1]: [Webmock](https://github.com/bblimke/webmock)

そこで思い切って「CSVエクスポート」自体をテーブルとして表現してみましょう。

```ruby
class Admin::UserExport < ApplicationRecord
  belongs_to :exported_by, class_name: "User"

  has_one_attached :csv

  store_accessor :conditions

  after_create -> { LaterJob.perform_later(self, :generate_and_notify) }

  def generate_and_notify
    csv.attach(generate_and_csv(User.search(conditions)))
    UserMailer.exported(exported_by, csv).deliver_later
  end
end
```

ここでの味噌は`after_create`で作成後にCSVを生成するjobをenqueueする部分です。CSVの生成自体はモデルに定義されていますが、`LaterJob`を呼び出すことにより実際のはbackground workerによって行われます。なお`after_create`では`after_create_commit`を使うべきと言う意見もあります。[^3]

`LaterJob`は与えられたobjectのmethodを呼び出すだけの非常に単純なjobです。

[^3]: [Prevent jobs from being scheduled within transactions](https://github.com/rails/rails/issues/26045)

```ruby
class LaterJob < ApplicationJob
  def perform(object, method) = object.public_send(method)
end
```

また`Admin::UserExport`を作成するcontrollerを考えてみると、scaffoldで生成されたCRUDのコードと同一と言って差し支えないでしょう。

```ruby
class Admin::UsersController < ApplicationController
  def create
    @export = UserExport.new(export_params)
    if @export.save
      redirect_to @export, notice: "エクスポートを開始しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def export_params
    params.
    require(:user_export).
    permit(conditions: {}).
    merge(exported_by: current_user)
end
```

最後にモデル部分のテストが容易に書けることを示します。Active Storageを使っているので、テスト時は自動でGCSからテスト可能なbackendに切り替えが行われます。

```ruby
class Admin::UserExportTest < ActiveSupport::TestCase
  test "作成後にjobをenqueueする" do
    export = Admin::UserExport.new(...)

    assert_enqueued_with job: LaterJob, args: [export, :generate_and_notify] do
      export.save!
    end
  end

  test "csvを作成する" do
    export = Admin::UserExport.create(...)

    assert_changes -> { export.csv.attached? }, from: false, to: true do
      export.generate_and_notify
    end
  end
end
```

まとめると以下の目標を達成する事が出来ました。

- HTTP requestがタイムアウトしない。
- HTTP serverのworkerを長時間占有しない。
- テストが容易に書ける。

RailsはActive RecordでHTTPリクエストとDBを串刺しにすることで、高い生産性を生み出しています。今回はそれを最大限利用するために、「CSVエクスポート」という動作自体をテーブルとして表現しました。これによりRailsが敷設したレールに乗ることが出来ました。

蛇足ですがこのパータンだとActive StorageのattachableとしてTempfileを渡したくなります。Railsにその旨のpull requestを送ってみました（この記事を書いている時点では取り込まれていません）。[^2]

[^2]: [Accept Tempfile as ActiveStorage attachable](https://github.com/rails/rails/pull/50862)
