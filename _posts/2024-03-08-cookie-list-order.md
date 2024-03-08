---
layout: post
title: "同じ名前のcookieが複数ある場合の仕様"
author: "@shouichi"
date: 2024-03-08 15:43:44 +09:00
tags:
  - http
  - rails
---

1つのRailsアプリケーションを複数のsubdomainで動かしているとします。デフォルトでsession storeはcookieなのでブラウザは以下のようなcookieを保持している状態になります。

```
_my_app=ABC; domain=www.example.com
```

Subdomain間でログイン状態を維持したくなったので、subdomain間で同じcookieを送る設定に変更したとします。

```ruby
module MyApp
  class Application < Rails::Application
    config.session_store :cookie_store, key: "_my_app", domain: :all
  end
end
```

変更後、sessionに値を書き込んで`Set-Cookie: _my_app=GHI; domain=.example.com`を返却したとします。するとブラウザは以下2つのcookieを保持することになります。

```
_my_app=ABC; domain=www.example.com
_my_app=EFG; domain=.example.com
```

この状態でブラウザが送信するリクエストのヘッダーは`Cookie: _my_app=ABC; _my_app=GHI`になります。同じ名前のcookieが複数ありますが、Railsからすると`ABC`の方のみしか見えません。結果としてsessionに書き込んだ値は全て無視されてしまいます。

```ruby
# https://github.com/rack/rack/blob/64ad26e3381da2ce1853638a2c4ea241c2ad3729/lib/rack/utils.rb#L223-L231
def parse_cookies_header(value)
  return {} unless value

  value.split(/; */n).each_with_object({}) do |cookie, cookies|
    next if cookie.empty?
    key, value = cookie.split('=', 2)
    # unless cookies.key?してるので、2つ目以降は無視される。
    cookies[key] = (unescape(value) rescue value) unless cookies.key?(key)
  end
end
```

対応としては単にcookie storeのkeyを変更すれば十分です。ただ、ブラウザがcookieを組み立てる際の順番が気になります。先ずはRFC[^1]で仕様を確認してみましょう。

[^1]: [HTTP State Management Mechanism](https://www.rfc-editor.org/rfc/rfc6265)

> 2 . The user agent SHOULD sort the cookie-list in the following
> order:
>
> - Cookies with longer paths are listed before cookies with
>   shorter paths.
> - Among cookies that have equal-length path fields, cookies with
>   earlier creation-times are listed before cookies with later
>   creation-times.

Pathが長い方を優先し、同じ場合は作成時刻が早い方を優先するとされています。最後に、この仕様通りに実装されているかChromiumのコードを覗いたところ、確かに仕様通りに実装されている事が確認出来ました。

```cpp
// https://github.com/chromium/chromium/blob/36b5627a5247893ed3cbfbc2fd569dc406b0b570/net/cookies/cookie_monster.cc#L580-L588
bool CookieMonster::CookieSorter(const CanonicalCookie* cc1,
                                 const CanonicalCookie* cc2) {
  // Mozilla sorts on the path length (longest first), and then it sorts by
  // creation time (oldest first).  The RFC says the sort order for the domain
  // attribute is undefined.
  if (cc1->Path().length() == cc2->Path().length())
    return cc1->CreationDate() < cc2->CreationDate();
  return cc1->Path().length() > cc2->Path().length();
}
```
