---
layout: post
title: "Global IDとpolymorphic associationの相性が良い"
author: "@shouichi"
date: 2025-06-19 10:36:28 +09:00
tags:
  - rails
---

Global ID[^1]（railsが内部的に依存しているライブラリ）とpolymorphic associationの相性が良いです。このことをGitHubようなシステムを例に見てみましょう。以下のmodelがあるとします。

[^1]: [rails/globalid: Identify app models with a URI](https://github.com/rails/globalid)

```ruby
class Issue
  has_many :comments, as: :commentable
end

class PullRequest
  has_many :comments, as: :commentable
end

class Comment
  belongs_to :commentable, polymorphic: true
end
```

IssueとPullRequestにはコメントが付けられます。コメントはpolymorphicになっており同じmodelが使い回されています。view/controllerも共通化したいので以下のようにするのが素直でしょう。

```erb
<%= form_with model: @comment do |form| %>
  <%= hidden_field_tag :commentable_type, @commentable.class %>
  <%= hidden_field_tag :commentable_id, @commentable.id %>

  <%= form.text_area :body %>
  <%= form.submit %>
<% end %>
```

```ruby
class CommentsController < ApplicationController
  before_action :set_commentable

  def create
    @comment = @commentable.comments.new(comment_params)
    if @comment.save
      redirect_to comment_path(@comment)
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_commentable
    commentable_type = params.require(:commentable_type).presence_in(%w[Comment PullRequest]) || raise ActionController::BadRequest
    @commentable = commentable_type.constantize.find(params.require(:commentable_id)
  end
end
```

`presence_in(%w[Comment PullRequest])`でコメント対象modelを限定しているのが重要です。これをしないと悪意のあるユーザーが、意図しないmodelにコメントを付けることが出来てしまいます。この書き方で大きな問題はないのですが、以下の点が気に食わないです。

- controllerがコメントを付けられるmodelを知っている（余計なドメイン知識がある）。
- コメントを付けられるmodelが増えたときにcontrollerを修正する必要がある。

Global IDを使うとこれら問題を解決しつつ、よりスッキリ書けます。それを紹介する前に、先ずは前提知識となるGlobal IDを簡単に紹介します。

```ruby
gid = Issue.find(1).to_global_id.to_s
#=> "gid://app/Issue/1"

GlobalID::Locator.locate(gid)
# => #<Issue:0x007fae94bf6298 @id="1">
```

Global IDは単純にclass/idをセットで文字列にエンコードしているだけです。さらに文字列が改竄出来ないように署名付きにすることも出来ます。

```ruby
sgid = Issue.find(1).to_global_id.to_s
#=> "BAhJIh5naWQ6Ly9pZGluYWlkaS9Vc2VyLzM5NTk5BjoGRVQ=--81d7358dd5ee2ca33189bb404592df5e8d11420e"

GlobalID::Locator.locate_signed(sgid)
# => #<Issue:0x007fae94bf6298 @id="1">
```

さあ、これを使ってview/controllerを書き換えてみましょう。

```erb
<%= form_with model: @comment do |form| %>
  <%= hidden_field_tag :commentable_signed_global_id, @commentable.to_signed_global_id %>
<% end %>
```

```ruby
class CommentsController < ApplicationController
  def set_commentable
    @commentable = GlobalID::Locator.locate_signed(params[:commentable_signed_global_id]) || raise(ActiveRecord::RecordNotFound)
  end
end
```

viewで`to_signed_global_id`を使いclass/idをセットで渡しつつ、改竄不可能にしているのが味噌です。改竄されていないことが保証されているので、controllerでは`GlobalID::Locator.locate_signed`を呼ぶだけで済んでいます。よって前述の気に食わない点を解決することが出来ています。

Global IDはrailsが内部的に使っているので、直接意識する機会は多くないでしょう。今回はそれを上手く使うことで、より洗練されたコードを書くことが出来ました。フレームワークやライブラリの内部を理解することの重要さが分かります。
