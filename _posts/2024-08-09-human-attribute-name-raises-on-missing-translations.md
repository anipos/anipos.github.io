---
layout: post
title: "翻訳がない場合にhuman_attribute_nameが例外を投げるようになりました"
author: "@shouichi"
date: 2024-08-09 16:56:00 +09:00
tags:
  - rails
---

Railsアプリケーションが日本語のみだとしても、I18nを使うと文言を一箇所に集約出来ます。これにより表記揺れし難くなる利点があります。この際に翻訳が存在しない場合に例外を投げるように設定しておくと、開発中に必ず気付けるので便利です。

```ruby
# > https://guides.rubyonrails.org/configuring.html#config-i18n-raise-on-missing-translations
# > Determines whether an error should be raised for missing translations. This defaults to false.
config.i18n.raise_on_missing_translations = true
```

こうしておくとview/controllerで存在しないI18nのkeyを指定した場合に例外が発生します。

```ruby
<%= t "key_that_does_not_exist" %>
#=> Translation missing: en.key_that_does_not_exist
```

```ruby
def create
  redirect_to @post, notice: t("key_that_does_not_exist")
end
#=> Translation missing: en.key_that_does_not_exist
```

ただしmodelは例外を投げてくれません。

```ruby
Post.human_attribute_name("title")
#=> "Title"
```

この挙動によりviewで長いI18nのkeyを指定する必要があり面倒です。

```html
<!-- 本当はこう書きたいが、翻訳がなくても例外が発生しない。 -->
<%= Post.human_attribute_name("title") %>

<!-- I18nのkeyを完全に指定する必要があり面倒。特にnestしたmodelの場合は長大になりがち。 -->
<%= t "activerecord.attributes.post.title" %>
```

そこで`human_attribute_name`が例外を投げるようにRails本体に修正を入れました。[^1]今回はその修正について解説します。

[^1]: [Change ActiveModel human_attribute_name to raise an error](https://github.com/rails/rails/pull/52426)

修正の要点は2つあります。

1. `ActiveModel::Translation`が例外を投げるオプションを加える。
2. Railtiesからそのオプションを設定する。

1点目は単純にオプションを追加して、そのオプションが有効の場合に例外を投げるようにするだけです。

```diff
--- a/activemodel/lib/active_model/translation.rb
+++ b/activemodel/lib/active_model/translation.rb
@@ -22,6 +22,8 @@ module ActiveModel
   module Translation
     include ActiveModel::Naming

+    singleton_class.attr_accessor :raise_on_missing_translations
+
     # Returns the +i18n_scope+ for the class. Override if you want custom lookup.
     def i18n_scope
       :activemodel
@@ -60,13 +62,17 @@ def human_attribute_name(attribute, options = {})
         end
       end

+      raise_on_missing = options.fetch(:raise, Translation.raise_on_missing_translations)
+
       defaults << :"attributes.#{attribute}"
       defaults << options[:default] if options[:default]
-      defaults << MISSING_TRANSLATION
+      defaults << MISSING_TRANSLATION unless raise_on_missing

-      translation = I18n.translate(defaults.shift, count: 1, **options, default: defaults)
+      translation = I18n.translate(defaults.shift, count: 1, raise: raise_on_missing, **options, default: defaults)
       translation = attribute.humanize if translation == MISSING_TRANSLATION
       translation
     end
   end
```

2点目はRailtiesから`config.i18n.raise_on_missing_translations`を`ActiveModel::Translation`に伝播させてやります。ただしRailsは機能ごとに有効化・無効化出来るので直接伝播させることは出来ません。今回の場合だとActive Modelが無効化されている場合があるので、それを考慮してやる必要があります。そこで`ActiveSupport::LazyLoadHooks`[^2]の出番です。

[^2]: [ActiveSupport::LazyLoadHooks](https://api.rubyonrails.org/classes/ActiveSupport/LazyLoadHooks.html)

Railsは機能ごとに有効化・無効化をするために内部的に粗結合に作られています。例えばAction CableではAction Viewがloadされた際に以下のコードを実行しています。これによりviewから`action_cable_meta_tag`が呼べるようになっています。

```ruby
# https://github.com/rails/rails/blob/9f80efc79119037fc4421d06e94a0d7e076876a4/actioncable/lib/action_cable/engine.rb#L19-L23
initializer "action_cable.helpers" do
  ActiveSupport.on_load(:action_view) do
    include ActionCable::Helpers::ActionCableHelper
  end
end
```

この仕組みは外部のgemでも使われています。例えば`turbo-rails`を使うと`turbo_frame_tag`などのhelperが使えるようになるのは、以下のコードによりRails本体が拡張されているからです。

```ruby
# https://github.com/hotwired/turbo-rails/blob/b0e7ebf2c7e2925c4d5fee4bf7d527c53ff4c1e3/lib/turbo/engine.rb#L59-L64
initializer "turbo.helpers", before: :load_config_initializers do
  ActiveSupport.on_load(:action_controller_base) do
    include Turbo::Streams::TurboStreamsTagBuilder, Turbo::Frames::FrameRequest, Turbo::Native::Navigation
    helper Turbo::Engine.helpers
  end
end
```

さて話を元に戻します。今回は`ActiveModel::Translation`がloadされた場合に限り`raise_on_missing_translations`を設定したいです。そこで`ActiveModel::Translation`がloadされた際のhookを追加します。

```diff
--- a/activemodel/lib/active_model/translation.rb
+++ b/activemodel/lib/active_model/translation.rb
@@ -68,5 +68,7 @@ def human_attribute_name(attribute, options = {})
       translation = attribute.humanize if translation == MISSING_TRANSLATION
       translation
     end
+
+    ActiveSupport.run_load_hooks(:active_model_translation, Translation)
   end
 end
```

次にload時に実行されるコードを追加します。

```diff
--- a/activesupport/lib/active_support/i18n_railtie.rb
+++ b/activesupport/lib/active_support/i18n_railtie.rb
@@ -83,6 +83,10 @@ def self.setup_raise_on_missing_translations_config(app)
         ActionView::Helpers::TranslationHelper.raise_on_missing_translations = app.config.i18n.raise_on_missing_translations
       end

+      ActiveSupport.on_load(:active_model_translation) do
+        ActiveModel::Translation.raise_on_missing_translations = app.config.i18n.raise_on_missing_translations
+      end
+
       if app.config.i18n.raise_on_missing_translations &&
           I18n.exception_handler.is_a?(I18n::ExceptionHandler) # Only override the i18n gem's default exception handler.
```

以上で翻訳がない場合に`human_attribute_name`が例外を投げるようになりました。

```ruby
# ActiveModel::Translation.raise_on_missing_translations = true
Post.human_attribute_name("title")
=> Translation missing. Options considered were: (I18n::MissingTranslationData)
    - en.activerecord.attributes.post.title
    - en.attributes.title

            raise exception.respond_to?(:to_exception) ? exception.to_exception : exception
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

これにてviewで長大なI18nのkeyを書かずとも済むようになりました。めでたし、めでたし。

余談ですが、この変更は既存のアプリケーションへの影響が大きいとの指摘が入りました。そこで追加で以下の変更を加えようとしています。なおこの記事を書いている段階では取り込まれていません。

- `raise_on_missing_translations`が`:strict`の場合に限り例外を投げる。[^3]
- modelごとに例外を投げる・投げないを設定出来る。[^4]

[^3]: [Change human_attribute_name to raise an error iff in strict mode](https://github.com/rails/rails/pull/52487)
[^4]: [Enable raising an error for missing translations on a per-model basis](https://github.com/rails/rails/pull/52495)
