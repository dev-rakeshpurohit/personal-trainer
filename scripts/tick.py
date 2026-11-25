import sys,re
m=sys.argv[1]
p='docs/07-BUILD-PLAN.md'
s=open(p).read()
start=s.index(f'## {m} ')
end=s.find('\n## ',start+3)
end=len(s) if end==-1 else end
s=s[:start]+s[start:end].replace('- [ ]','- [x]')+s[end:]
open(p,'w').write(s)
