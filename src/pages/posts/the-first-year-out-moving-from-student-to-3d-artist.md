---
layout: '../../layouts/MarkdownPost.astro'
title: '如何复刻本网站，零氪快速建博客'
pubDate: 2024-8-01
description: '如何复刻本网站，零氪快速建博客'
author: 'nobody'
cover:
    url: 'https://cdn.sanity.io/images/3tyxzjdw/production/fceb5bd36c9945dc65f093616f7a472426cbc656-912x512.png'
    square: 'https://cdn.sanity.io/images/3tyxzjdw/production/fceb5bd36c9945dc65f093616f7a472426cbc656-912x512.png'
    alt: 'cover'
tags: ["特写", "影视", "教育", "游戏", "3d", "新闻稿"]
theme: 'dark'
featured: true
---




本站包括以下可完全免费部署的功能：

主页（/）
博客（/blog，附带评论系统）
项目列表（/projects）
留言墙（/guestbook）
后台 CMS（/studio，发布管理文章，编辑项目列表等）
Admin 后台（/admin，查看评论数据，发送 Newsletter 等）
修改简历(

Resume.tsx)
修改首页图片（

Photos.tsx）
修改首页简介（

Headline.tsx）
修改导航条（

nav.ts）
以下是网站必需的第三方服务：

Vercel（部署服务平台，可白嫖）
Sanity（后台 CMS，可白嫖）
PlanetScale（MySQL 数据库，用来承载评论系统、Newsletter 系统与留言墙，可白嫖）
Resend（Email 发送服务，可白嫖）
Upstash（Redis 服务，涉及文章阅读量，文章表情回复和网站访问量，可白嫖）
以下是可选的第三方服务：



urlbox （用来生成链接预览快照图，$9/月）
项目克隆与本地配置
好，接下来我们正片开始。

首先将我的 

GitHub repo 通过 fork 的形式，克隆到你自己的 GitHub 账号里。

然后将此 repo 通过 git clone 的形式拷贝到你的电脑本地文件夹中。

这个时候，确保你本地已经安装了 

pnpm。

首先我们需要 cd 到你克隆好的本地目录下运行命令行：

1pnpm i

来安装依赖 node_modules 依赖库。

Sanity 内容管理
安装完成以后我们需要先配置一下我们的 Sanity 来做我们的后台 CMS（内容管理系统）。

前往 

sanity.io/manage 登录
回到命令行，运行 npm create sanity@latest -- --template clean --create-project "Cali Demo" --dataset production，记得把「Cali Demo」替换成你的项目名称
按 Ctrl + C 退出命令即可
回到 

Sanity Dashboard 刷新一下页面，如果你看到了：

就说明成功创建了我们的 Sanity project 🎉

点进去查看 project 详情，我们需要复制 Project ID，如下图所示：

在本地项目目录下运行：

1cp .env.example .env

下面我们打开编辑器，开始编辑我们的 .env 环境变量文件。

将 Sanity CMS 区域变量填入你自己真实的数值：

.env

1NEXT_PUBLIC_SANITY_DATASET="production" 2NEXT_PUBLIC_SANITY_PROJECT_ID="你的 project ID"

Clerk 用户鉴权
为了实现网站的用户登录功能，我们需要使用 

Clerk 的帮助。

我们只需：

前往 

clerk.com
点击右上角 Sign up 注册
在 Dashboard 页面点击 Add application
填入你的项目名字，选择你想打开的鉴权机制（邮箱，Google，GitHub 等）
就完成了 Clerk 的应用注册，非常简单！

然后我们只需点击拷贝按钮，复制一下这个环境变量，如图：

回到我们本地项目的 .env 文件，替换掉 Clerk 区域的两行即可 🎉。

PlanetScale 数据库
为了实现网站的评论、留言和 Newsletter 等功能，我们需要 

PlanetScale 的数据库帮助。

步骤如下：

前往 

PlanetScale 官网
点击右上角 Sign in 或 Get started
根据后台步骤提示创建一个 database
选择 Hobby（白嫖版）
输入数据库名称
选择 region 的时候需要注意，你现在选择的区域要在等会配置 Vercel 的时候选择对应的 region，个人推荐「新加坡」
示例：

点击底下的 Create database 就创建完成 🎉

这个时候，我们需要获取数据库的信息才能让项目正确连接：

点击 connect to your database 以后会让你创建一个 password，直接点创建即可。

在 Connect with 的下拉菜单中选择「@planetscale/database」

拷贝 .env 到我们本地项目的环境变量即可。

但我们还需要一个变量是 DATABASE_URL ，我们需要在下拉菜单再次选择成 Prisma 即可获取到一个 URL，同样复制粘贴到项目内的 .env 中。

注意：我们需要把 DATABASE_URL 最后的 ?sslaccept=strict 删除掉，替换成 ?ssl={"rejectUnauthorized":true}
现在你的 .env 应该看起来跟我的差不多了：

示例 .env 文件

为了部署我们的数据库，我们需要在命令行中运行：

1pnpm db:push

看到 Changes applied 就说明成功了 👍。

回到 PlanetScale 里面查看你的 main branch，图示：

数据库就大功告成啦 🎉

Resend 邮件发送
为了发送邮件，我们需要借助 

Resend 的力量。

以下情况会发送邮件：

当有人订阅 Newsletter 时，我们发送订阅确认的邮件
当有人回复他人评论时，我们发送邮件给被回复者
当有人在留言墙留言时，我们发送邮件给SITE_NOTIFICATION_EMAIL_TO
所以我们需要配置一下 SITE_NOTIFICATION_EMAIL_TO 为你想接收新留言提醒的邮箱地址，在 .env 里：

.env

1SITE_NOTIFICATION_EMAIL_TO="yourname@example.com"

我们接下来前往 Resend 后台创建获取我们的 API key 吧：

前往 

Resend 官网
注册/登录
点击 Add an API Key
就这么简单，我们复制一下 API key 到 .env 中去替代 RESEND_API_KEY 即可。

Upstash 访问统计& API 限流
为了给网站添加总访问量和文章的浏览量，我们需要注册一个 Upstash 账号。

步骤：

前往 

Upstash 官网
登录
点击 Create database
填入名称，Type 选 Global，Primary region 选「PlanetScale 选择的区域」，依然推荐新加坡
找到 REST API 区域
如图：

复制这两个值，然后我们需要回到 .env 中填入：

.env

1UPSTASH_REDIS_REST_TOKEN="****" 2UPSTASH_REDIS_REST_URL="https://***.upstash.io"

链接预览快照图
如果你也想有链接预览快照图的话，可以前往 

urlbox.io 注册账号，并填入你的 API URL 到环境变量 LINK_PREVIEW_API_BASE_URL 中

因为是一个必须收费的服务，这里不推荐所有人使用，不过如果你愿意花钱的话也没问题。

⚠️ 注意：如果你不需要这个链接快照图功能的话，请编辑项目中的components/links/PeekabooLink.tsx 第15行，改成 false，才能确保下一步部署的正常。
Vercel 部署
最后一步至关重要，我们需要前往 Vercel 进行部署我们的项目，步骤：

前往 

Vercel 官网
登录/注册
在 Dashboard 里选择 Add new project
从 GitHub 导入你 fork 后的仓库
如下图所示

我们展开 Environment variables 区域，并回到我们本地的 .env 文件中，复制全部内容（除了最后的 Vercel 的两个变量），回到网页中，点击输入框，按粘贴。

⚠️ 如果你遇到了部署问题（比如 Error: Invalid environment variables，请检查上一步「链接快照图」中的步骤，是不是没有更改代码）
然后我们在 Vercel 项目的标签中选择 Storage，并创建一个 Edge Config 实体，如图：

这么做的目的是我们可以将一些站点配置存储在 Edge Config 中，从而达到跟仓库的代码解耦脱离出来。

然后我们可以填入以下 json 到我们刚创建好的 Edge Config Store 中：

Edge Config Store

1{ 2 "redirects": [ 3 { 4 "source": "/twitter", 5 "destination": "https://twitter.com/thecalicastle", 6 "permanent": true 7 }, 8 { 9 "source": "/github", 10 "destination": "https://github.com/CaliCastle", 11 "permanent": true 12 }, 13 { 14 "source": "/bilibili", 15 "destination": "https://space.bilibili.com/8350251", 16 "permanent": true 17 } 18 ], 19 "blocked_ips": [] 20}

redirects 里定义了我们设置的重定向规则，比如访问我们网站的 /twitter 以后就会重定向到我们的 destination 链接去，以此类推。
blocked_ips 里定义了所有我们需要黑名单的 IP 地址字符串，比如“blocked_ips”: [“1.1.1.1”]
如图所示：

最后别忘了点击 Save Items。

为了让我们本地正确使用 Edge Config，我们需要前往 Vercel 项目的 Settings 下的 Environment Variables 界面：

复制一下 EDGE_CONFIG 到我们本地的 .env 文件底部去。

最后所有配置就都大功告成了 🎉，最后在左侧的 Functions 配置，选择上述相同的 region，还是推荐新加坡。

发布和管理文章
为了发布管理文章，我们只需要访问 /studio 即可前往到我们项目内的 Sanity Studio

第一次访问的话，Sanity 会跳出提示：

我们点击 Continue 即可。

然后根据提示，点击 Add CORS origin。

用一开始登录 Sanity 的账号登录即可。

现在就应该可以看到我们的 Studio 页面了：

发布文章
（见上图）我们只需点击 1，然后 2，即可发布一篇新文章。

编辑的顺序从上到下，给文章的名字（Title），url 的 slug（英文句子，连字符代替空格），填入类别，发布时间，一张文章图片，和文章描述。

Body 就是我们编辑的文章正文，在我们编辑完以后记得点击下面的 Reading time 可以一键生成阅读时间。

最后全部编辑完成以后就可以点右下角的 Publish 了。

文章发布就是这么简单 👏

管理文章
其实管理文章跟上述发布的流程差不多，只不过在文章列表里选中你想编辑的文章，然后在右侧编辑以后再次点击 Publish 按钮即可。

配置生产环境域名
记得前往 

Sanity 后台的项目设置中，填入你的最终部署的域名，如图：

在 3 填入你的完整域名 URL，比如 https://cali.so，最后位置 4 记得打上勾即可。

后台 Admin
为了访问到我们的后台 Admin 页面，我们首先需要回到 Clerk 的后台界面中：

（如果你还没有登录的话，在本地页面记得点击右上角登录一下，或者直接访问本地的 /admin 会重定向到登录页面）

选中我们自己登录的账号详情，我们需要滚动到下面的 Metadata 区域：

点击 Public 旁边的 Edit：

替换内部的 json 变成：

1{ 2 "siteOwner": true 3}

这样就可以标示这名用户可以进入我们的 admin 后台了，保存即可。

现在在本地项目访问 /admin 就可以看到正常的访问了：

发布 Newsletter
要想发布新的 Newsletter 也可以在 admin 里操作，只需点击左侧的 Newsletters 然后点击 New 即可进入创建页面。

Body 输入 markdown 即可。
