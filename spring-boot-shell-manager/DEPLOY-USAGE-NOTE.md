# Deploy Script 使用要点

## 📍 重要说明

### `.fuyou` 配置文件位置

**关键点：** `.fuyou` 配置文件位于 **执行 `deploy.sh` 时的当前工作目录**。

```bash
# deploy.sh 的逻辑
PROJECT_ROOT="$(pwd)"              # 当前工作目录
CONFIG_FILE="$PROJECT_ROOT/.fuyou" # 配置文件路径
```

### 正确的使用方式

#### ✅ 推荐：将 deploy.sh 放在项目根目录

```bash
# 目录结构
your-spring-boot-project/
├── pom.xml
├── src/
├── deploy.sh          # 复制到项目根目录
└── .fuyou             # 自动生成在项目根目录

# 使用方法
cd your-spring-boot-project
./deploy.sh --init /path/to/deploy
./deploy.sh
```

**优点：**

- ✅ 配置文件和项目在一起，便于管理
- ✅ 可以加入 `.gitignore`，每个开发者独立配置
- ✅ 清晰明了，不会混淆

#### ✅ 也可以：从子目录执行

```bash
# 目录结构
your-spring-boot-project/
├── pom.xml
├── src/
├── .fuyou                         # 配置文件在项目根目录
└── spring-boot-shell-manager/
    └── deploy.sh                  # 脚本在子目录

# 使用方法（注意要从项目根目录执行）
cd your-spring-boot-project
./spring-boot-shell-manager/deploy.sh --init /path/to/deploy
./spring-boot-shell-manager/deploy.sh
```

**注意：**

- ⚠️ 必须从项目根目录执行（不能 cd 到 spring-boot-shell-manager）
- ⚠️ `.fuyou` 仍然在项目根目录

#### ❌ 错误：在脚本所在目录执行

```bash
# 错误的做法
cd your-spring-boot-project/spring-boot-shell-manager
./deploy.sh --init /path/to/deploy

# 结果：.fuyou 会生成在 spring-boot-shell-manager 目录
# Maven 找不到 pom.xml，构建失败
```

## 🎯 多项目场景

### 场景：多个子项目，各自独立配置

```bash
workspace/
├── project-a/
│   ├── pom.xml
│   ├── src/
│   ├── deploy.sh              # 复制的脚本
│   └── .fuyou                 # 项目A的配置
├── project-b/
│   ├── pom.xml
│   ├── src/
│   ├── deploy.sh              # 复制的脚本
│   └── .fuyou                 # 项目B的配置
└── project-c/
    ├── pom.xml
    ├── src/
    ├── deploy.sh              # 复制的脚本
    └── .fuyou                 # 项目C的配置
```

**部署流程：**

```bash
# 项目A
cd workspace/project-a
./deploy.sh --init /deploy/app-a
./deploy.sh

# 项目B
cd workspace/project-b
./deploy.sh --init /deploy/app-b
./deploy.sh

# 项目C
cd workspace/project-c
./deploy.sh --init /deploy/app-c
./deploy.sh
```

**优点：**

- ✅ 每个项目完全独立
- ✅ 配置互不干扰
- ✅ 可以部署到不同目录
- ✅ 每个项目的 `.fuyou` 可以加入该项目的 `.gitignore`

## 📋 最佳实践

### 1. 项目根目录放置

```bash
# 将 deploy.sh 复制到项目根目录
cp spring-boot-shell-manager/deploy.sh ./

# 添加到 .gitignore
echo ".fuyou" >> .gitignore
```

### 2. IDE 配置

**IntelliJ IDEA:**

- Working Directory: `$ProjectFileDir$`
- Script: `./deploy.sh`（或 `spring-boot-shell-manager/deploy.sh`）
- Environment: `DEPLOY_DIR=/path/to/deploy`（可选）

**VS Code tasks.json:**

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Deploy to Local",
      "type": "shell",
      "command": "./deploy.sh",
      "options": {
        "cwd": "${workspaceFolder}",
        // 项目根目录
        "env": {
          "DEPLOY_DIR": "/path/to/deploy"
        }
      }
    }
  ]
}
```

### 3. 团队协作

**方案A：每人独立配置**

```bash
# 每个开发者
echo ".fuyou" >> .gitignore
./deploy.sh --init ~/my-deploy-dir
```

**方案B：使用环境变量**

```bash
# 不生成 .fuyou，直接用环境变量
DEPLOY_DIR=/path/to/deploy ./deploy.sh

# 或在 IDE 中配置
```

### 4. CI/CD 集成

```bash
# Jenkinsfile / GitLab CI
script:
  - cd project-root
  - export DEPLOY_DIR=/opt/deploy/app
  - ./deploy.sh
```

## ⚠️ 常见问题

### Q: 为什么 `.fuyou` 不在脚本所在目录？

A: 因为 `deploy.sh` 使用 `$(pwd)` 获取当前工作目录，而不是脚本所在目录。这样设计的好处是：

- ✅ 配置文件跟随项目，不跟随脚本
- ✅ 更灵活，可以从任何位置调用脚本
- ✅ 符合"在项目根目录执行构建命令"的习惯

### Q: 如何在多个项目间共享脚本？

A: 两种方式：

**方式1：各自复制**

```bash
# 每个项目复制一份
cp spring-boot-shell-manager/deploy.sh project-a/
cp spring-boot-shell-manager/deploy.sh project-b/
```

**方式2：共享脚本，各自配置**

```bash
# 共享脚本位置
tools/deploy.sh

# 从各项目根目录调用
cd project-a && ../tools/deploy.sh --init /deploy/app-a
cd project-b && ../tools/deploy.sh --init /deploy/app-b
```

### Q: Maven 找不到 pom.xml？

A: 检查是否从项目根目录执行：

```bash
# ✅ 正确
cd /path/to/spring-boot-project
./deploy.sh

# ❌ 错误
cd /path/to/spring-boot-project/spring-boot-shell-manager
./deploy.sh
```

## 📚 相关文档

- [README.md](README.md) - 主文档
- [DEPLOY.md](DEPLOY.md) - 详细部署指南
- [TEST-SUMMARY.md](TEST-SUMMARY.md) - 测试总结

## 🔄 版本历史

- **v2.0** (2025-11-23)
    - 修复配置文件路径问题
    - 配置文件现在在当前工作目录（项目根目录）
    - 支持多项目独立配置

- **v1.0** (2025-11-23)
    - 初始版本
    - 通用化部署脚本
