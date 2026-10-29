import re,sys,pathlib,collections
root=pathlib.Path(sys.argv[1])
loop=re.compile(r'^\s*(for .+ in .+\{|while .+\{)|\.(forEach|map|compactMap|flatMap|filter|reduce)\s*\{')
inner=re.compile(r'\.(first\s*\{|first\(where|contains\s*\{|contains\(where|firstIndex|lastIndex|filter\s*\{|sorted|removeFirst\(\))')
hits=collections.Counter(); out=[]
for f in sorted(root.rglob('*.swift')):
    lines=f.read_text().splitlines()
    for i,l in enumerate(lines):
        if not loop.search(l): continue
        depth=l.count('{')-l.count('}'); j=i+1
        if depth<=0:
            # single-line closure: inspect remainder after loop token
            m=loop.search(l); rest=l[m.end():]
            if inner.search(rest): out.append((str(f.relative_to(root)),i+1,l.strip()[:150])); hits[str(f.relative_to(root))]+=1
            continue
        while j<len(lines) and depth>0 and j<i+60:
            s=lines[j]
            if inner.search(s): out.append((str(f.relative_to(root)),j+1,s.strip()[:150])); hits[str(f.relative_to(root))]+=1; break
            depth+=s.count('{')-s.count('}'); j+=1
for k,v in hits.most_common(40): print(v,k)
pathlib.Path(sys.argv[2]).write_text('\n'.join(f'{a}:{b}: {c}' for a,b,c in out))
print(len(out))
