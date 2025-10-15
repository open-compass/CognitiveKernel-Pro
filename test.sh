# 1. 获取浏览器
BROWSER_ID=$(curl -s -X POST http://localhost:3001/getBrowser \
  -H "Content-Type: application/json" \
  -d '{}' | grep -o '"browserId":"[^"]*"' | cut -d'"' -f4)

echo "Browser ID: $BROWSER_ID"

# 2. 打开页面
curl -s -X POST http://localhost:3001/openPage \
  -H "Content-Type: application/json" \
  -d "{\"browserId\":\"$BROWSER_ID\",\"url\":\"https://www.google.com\"}"

# 应该返回: {"browserId":"xxx","pageId":"0"}