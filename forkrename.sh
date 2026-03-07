# 1. Define the old and new paths
OLD="github.com/jindong-pan/picoclaw"
NEW="github.com/jindong-pan/picoclaw"

# 2. Find all files containing the old path and replace it
# We exclude the .git directory to avoid breaking your commit history
grep -rl "$OLD" . --exclude-dir=.git | xargs sed -i "s|$OLD|$NEW|g"

# 3. Synchronize the Go modules
go mod tidy
