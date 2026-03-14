# GMN Usage Monitor

本地监控页，用来持续读取 `https://gmn.chuangzuoli.com/subscriptions` 的订阅和用量，并在登录态过期时自动续期或自动重登。

截至 `2026-03-11`，当前站点的真实结构是：

- 页面是 Vue SPA，`/subscriptions` 本身只返回前端入口 HTML。
- API 基础路径是 `/api/v1`。
- 订阅页面主接口是 `GET /api/v1/subscriptions`。
- 前端还存在这些订阅接口：
  - `GET /api/v1/subscriptions/active`
  - `GET /api/v1/subscriptions/progress`
  - `GET /api/v1/subscriptions/summary`
  - `GET /api/v1/subscriptions/:id/progress`
- 认证接口：
  - `POST /api/v1/auth/login`
  - `POST /api/v1/auth/login/2fa`
  - `POST /api/v1/auth/refresh`
  - `GET /api/v1/auth/me`
  - `POST /api/v1/auth/logout`
- 站点前端使用的本地存储键：
  - `auth_token`
  - `refresh_token`
  - `token_expires_at`
  - `auth_user`

## 功能

- 拉取并展示当前订阅卡片
- 展示每日 / 每周 / 每月：
  - 已用
  - 总额度
  - 剩余额度
  - 进度条
  - 重置倒计时
- 展示订阅到期时间和状态
- 登录态快到期时优先走 `refresh_token`
- `refresh_token` 失效后，如果已保存凭据，则自动重新登录
- 如果账户开启 TOTP 2FA，支持填入 Base32 secret 或 `otpauth://` URI 来自动补 2FA

## 启动

```bash
cd /Users/bigzi/service/gmn-usage-monitor
node server.js
```

然后访问：

```text
http://127.0.0.1:3210
```

## 配置方式

可以二选一：

1. 用页面登录，然后勾选“保存凭据用于自动重登”
2. 复制 `config.example.json` 为 `config.json`，直接填账号密码

也支持环境变量：

```bash
GMN_EMAIL=you@example.com
GMN_PASSWORD=your-password
GMN_TOTP_SECRET=BASE32_OR_OTPAUTH_URI
PORT=3210
```

## 安全说明

- 自动重登意味着需要把账号密码保存在本机。
- 本工具会把凭据写到 `data/credentials.json`，不会进 git。
- 这个文件只适合保存在你自己的机器上。
