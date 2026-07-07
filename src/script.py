find ./lesguillemards/to_upgrade -type f \( -name "*.py" -o -name "*.xml" -o -name "*.csv" -o -name "*.js" \) \
  -exec python3 -c "
import sys
try:
    open(sys.argv[1], encoding='utf-8').read()
except UnicodeDecodeError:
    print(sys.argv[1])
" {} \;
