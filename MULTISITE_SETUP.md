# FrankenWP 多站点设置与管理指南

本文档介绍如何使用 `frankenwp` 项目设置和管理基于 Caddy 和 FrankenPHP 的 WordPress 多站点环境。

## 概述

此设置利用 Caddy 作为 Web 服务器和 FrankenPHP 作为高性能 PHP 应用服务器来托管多个独立的 WordPress 站点。每个站点拥有自己的域名和文件目录。

核心组件：

*   **`Caddyfile.multisite`**: Caddy 服务器的配置文件模板。全局设置在此定义，站点特定的配置由管理脚本动态添加/删除。
*   **`manage_sites.sh`**: 一个 Bash 脚本，用于简化向 `Caddyfile.multisite` 添加和删除站点配置的过程。
*   **Docker Compose**: (`examples/docker-compose.yml`) 用于编排 PHP 环境 (FrankenPHP/Caddy) 和数据库服务。
*   **站点目录**: 默认情况下，所有站点的文件应位于宿主机上相对于 `examples/docker-compose.yml` 的 `../sites/` 目录下，每个站点一个子目录 (例如 `../sites/site1`, `../sites/site2`)。这些目录会被挂载到容器内的 `/var/www/sites/`。

## 初始设置

1.  **准备站点文件**:
    *   在宿主机上创建 `sites` 目录 (如果尚不存在)，与 `examples` 目录同级。
    *   对于您要托管的每个 WordPress 站点，在 `sites` 目录下创建一个子目录 (例如 `sites/my-site-1`, `sites/my-site-2`)。
    *   将每个站点的 WordPress 核心文件、`wp-config.php` 和 `wp-content` 放入其各自的子目录中。确保每个站点的 `wp-config.php` 配置了正确的数据库连接信息（数据库主机通常是 `db`，即 Docker Compose 中的服务名）。

2.  **配置 Caddyfile 模板**:
    *   打开 `Caddyfile.multisite` 文件。
    *   找到 `email your-email@example.com` 这一行。
    *   **重要**: 将 `your-email@example.com` 替换为您自己的有效电子邮件地址。这对于 Let's Encrypt 自动获取 SSL 证书至关重要。

3.  **启动服务**:
    *   进入 `examples` 目录。
    *   运行 `docker compose up -d` (或根据您的示例文件，例如 `docker compose -f basic/compose.yaml up -d`) 来构建并启动服务。

## 使用 `manage_sites.sh` 管理站点

`manage_sites.sh` 脚本位于项目根目录，用于向 `Caddyfile.multisite` 添加或删除站点配置。

**重要**: 每次使用脚本修改 `Caddyfile.multisite` 后，您都需要重新加载 Caddy 配置以使更改生效。

### 1. 添加站点

使用 `add` 命令添加一个新的站点配置。

**语法**:

```bash
./manage_sites.sh add <domain> <site_dir>
```

**参数**:

*   `<domain>`: 您要添加的站点的完整域名 (例如 `blog.example.com`)。
*   `<site_dir>`: 该站点文件在 `sites` 目录下的子目录名称 (例如 `my-blog`)。脚本会自动将其映射到容器内的 `/var/www/sites/<site_dir>`。

**示例**:

假设您在宿主机的 `sites/my-blog` 目录下准备好了站点文件，并且希望通过 `blog.example.com` 访问它：

```bash
./manage_sites.sh add blog.example.com my-blog
```

此命令将在 `Caddyfile.multisite` 中 `# <<< SITE_CONFIGURATIONS_BELOW >>>` 标记之前插入类似以下的配置块：

```caddyfile
# --- blog.example.com Configuration ---
blog.example.com {
    root * /var/www/sites/my-blog
    encode br zstd gzip
    php_server
    try_files {path} {path}/index.php?{query}
    file_server
    # Add site-specific directives here if needed
}
```

### 2. 删除站点

使用 `remove` 命令删除一个现有的站点配置。

**语法**:

```bash
./manage_sites.sh remove <domain>
```

**参数**:

*   `<domain>`: 您要移除的站点的域名 (例如 `blog.example.com`)。

**示例**:

```bash
./manage_sites.sh remove blog.example.com
```

此命令将在 `Caddyfile.multisite` 中查找并删除与 `blog.example.com` 相关的整个配置块（包括其前面的注释行）。

### 3. 应用更改 (重新加载 Caddy)

在添加或删除站点后，Caddy 需要重新加载其配置。假设您的 PHP/Caddy 服务在 Docker Compose 中名为 `php_env` (请根据您的 `docker-compose.yml` 文件确认服务名)，并且您在 `examples` 目录下，可以运行以下命令：

```bash
docker compose exec php_env caddy reload --config /etc/caddy/Caddyfile
```

*   **注意**: `docker-compose.yml` 将宿主机的 `Caddyfile.multisite` 挂载到了容器内的 `/etc/caddy/Caddyfile`。因此，重新加载时要指定容器内的路径。

如果命令成功执行，Caddy 将无缝应用新的配置，您的添加或删除操作将生效。

---

现在您可以使用此脚本和流程来轻松管理您的 FrankenWP 多站点环境。