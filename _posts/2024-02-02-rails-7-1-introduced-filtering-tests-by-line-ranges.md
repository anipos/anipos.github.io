---
layout: post
title: "Rails 7.1で指定した範囲の行にあるテストを実行可能になりました"
author: "@shouichi"
date: 2024-02-02 17:26:14 +09:00
categories: rails
---

Rails 7.1では、指定した行の範囲内に宣言されたテストのみを実行する機能が加わりました。例えば、以下のコマンドは`user_test.rb`の10〜20行目に宣言してあるテストを実行します。

```bash
$ ./bin/rails test test/models/user_test.rb:10-20
```

ある機能Aを開発・改修するとして、Aに関するテストはファイル上の近い場所に宣言される事が多いでしょう。またAに関するコードを書く際は、Aに関するテストを全て実行したくなります。7.1で入った表題の機能はまさにうってつけの機能です。

何を隠そう、この機能はアニポスがRailsに加えたものなのです。[^1]アニポスでモブプログラミングをしている際に、表題の機能がなく不便だったので、pull requestを送りました。その時のモブプロ参加者である以下のメンバーがco-authorとなっています。

- @RyochanUedasan
- @oljfte
- @sgyang
- @shouichi

[^1]: [Support filtering tests by line ranges](https://github.com/rails/rails/pull/48807)

機能の追加自体は簡単で、コマンドラインの引数をパースする際の正規表現を調整する程度でした。

```patch
--- a/railties/lib/rails/test_unit/runner.rb
+++ b/railties/lib/rails/test_unit/runner.rb
@@ -4,6 +4,7 @@
 require "rake/file_list"
 require "active_support"
 require "active_support/core_ext/module/attribute_accessors"
+require "active_support/core_ext/range"
 require "rails/test_unit/test_parser"

 module Rails
@@ -68,7 +69,7 @@ def extract_filters(argv)

               path = path.tr("\\", "/")
               case
-              when /(:\d+)+$/.match?(path)
+              when /(:\d+(-\d+)?)+$/.match?(path)
                 file, *lines = path.split(":")
                 filters << [ file, lines ]
                 file
@@ -155,17 +156,21 @@ def derive_line_filters(patterns)
     end

     class Filter # :nodoc:
-      def initialize(runnable, file, line)
+      def initialize(runnable, file, line_or_range)
         @runnable, @file = runnable, File.expand_path(file)
-        @line = line.to_i if line
+        if line_or_range
+          first, last = line_or_range.split("-").map(&:to_i)
+          last ||= first
+          @line_range = Range.new(first, last)
+        end
       end

       def ===(method)
         return unless @runnable.method_defined?(method)

-        if @line
+        if @line_range
           test_file, test_range = definition_for(@runnable.instance_method(method))
-          test_file == @file && test_range.include?(@line)
+          test_file == @file && @line_range.overlaps?(test_range)
         else
           @runnable.instance_method(method).source_location.first == @file
         end
```

さて、これを実装している際に`Range#overlaps?`がRubyではなくActive Supportで実装されている事に気付きました。これは当然Rubyにあって然るべきだろうと考え、Ruby本体にも`Range#overlap?`を追加するpull requestを送り、こちらもRuby 3.3の一部としてリリースされました。[^2]

[^2]: [[Feature #19839] Add Range#overlap?](https://github.com/ruby/ruby/pull/8242)

ただ、一見単純に思えた`Range#overlaps?`も様々なコーナケースがあり、取り込まれるまでには一悶着ありました。[^3]例えば以下の例は当初のActive Supportを移植したバージョンでは`true`を返しますが、Ruby 3.3では`false`を返します。

```ruby
(1..2).overlap?(2...2)
(2..2).overlap?(2...2)
(2...2).overlap?(2...2)
```

[^3]: [Need a method to check if two ranges overlap](https://bugs.ruby-lang.org/issues/19839)

コーナーケースついてはRubyのissue trackerでのやり取りで、`Range`が`succ-based`と`cover-based`の2つのセマンティクスを内包している事など、多くを学ぶこと出来ました。詳しくはakrさんの記事を参照してください。[^4]

[^4]: [#1 Ruby の Range#empty? は実装可能か?](http://www.a-k-r.org/d/2023-09.html#a2023_09_28_1)

Railsに機能を追加することから始まり、Ruby自体にも貢献出来たことは、個人的に大きな喜びでした。これからもアニポスを通じてオープンソースコミュニティへの貢献出来れば幸いです。
