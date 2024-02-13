---
layout: post
title: "GitHubもTerraformで管理する"
author: "@shouichi"
date: 2024-02-13 14:09:15 +09:00
tags: terraform
---

アニポスではインフラを全てterraformで管理しています。一度terraformに慣れてしまうと手動での設定が億劫になるものです。githubも手動で設定するのは面倒ですし、チームやリポジトリ数が増えるに従い、一貫した設定を適用するのは難しくなります。そこでアニポスではgithubもterraformの管理下に置いて設定をコード化しています。これには幾つかの利点があります。

先ずterraformのコードは当然git管理されているので、githubの設定を変更する場合も通常の開発と同様、pull requestを通して行われます。これにより手動での設定変更と比較してミスの防止になりますし、変更履歴の追跡も`git log`するだけと容易です。例えばこのブログ向けのリポジトリに関連した`git log --oneline`が以下です。

```
95d38dd anipos.github.ioのhomepage urlを設定 (#506)
ded00e6 anipos.github.ioのstatus checkを厳格化 (#502)
beda597 anipos.github.ioのgithub pagesを有効化 (#499)
2f63c38 anipos.github.ioリポジトリ作成 (#497)
```

またterraform moduleによりチームやリポジトリの設定を共通化出来ます。例えばcode reviewを交互に行う設定を全チームに適用しています。

```hcl
resource "github_team_settings" "team_settings" {
  team_id = github_team.team.id

  review_request_delegation {
    algorithm    = "ROUND_ROBIN"
    member_count = 2
    notify       = true
  }
}
```

別の例として、全てのリポジトリに`lgtm`ラベルを設定しています。アニポスでは`lgtm`ラベルが付いたpull requestはテスト通過後にbulldozer[^1]により自動で取り込まれます。

```hcl
resource "github_issue_label" "lgtm" {
  repository  = github_repository.repository.name
  name        = "lgtm"
  color       = "38d87b"
  description = "PRs with this label will be merged by bulldozer (when possible)."
}
```

[^1]: [bulldozer](https://github.com/palantir/bulldozer)

実際のpull requestを一例に流れを見てみましょう。

1. @RyochanUedasanがチームメンバーを追加するpull requestを作成。
1. atlantis[^2]がterraform planを実行し結果をコメント。
1. @shouichiがplan結果を確認しapprove。
1. @RyochanUedasanがatlantisにapplyを命令、また`lgtm`ラベルを付与。
1. bulldozer[^1]がそれを検知してmerge。

![pull requestの一例](/assets/2024-02-13-managing-github-organizations-using-terraform.png)

[^2]: [Atlantis](https://www.runatlantis.io)

上記の例から分かるように、アニポスでは厳密な権限管理をしている一方で、メンバーが能動的に権限を手に入れられる、風通しの良い環境になっています。これはgithubをterraform管理することの嬉しい副作用でした。
