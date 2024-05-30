#!/bin/bash

# 获取程序名称
PROGRAM="umes"

# 获取当前时间作为构建时间
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 获取当前 Git 分支名称
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)

# 获取当前 Git 提交哈希
COMMIT_HASH=$(git rev-parse HEAD)

# 创建 version.json 文件
cat <<EOF > version.json
{
    "program": "$PROGRAM",
    "buildTime": "$BUILD_TIME",
    "branchName": "$BRANCH_NAME",
    "commitHash": "$COMMIT_HASH"
}
EOF

echo "version.json 文件已生成"
