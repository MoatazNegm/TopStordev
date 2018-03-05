import sys
import json
hi=sys.argv[1]
res=0
#pp=hi[1:len(hi)-1];
try:
  data=json.loads(hi);
except:
  res=1;
print(res)
