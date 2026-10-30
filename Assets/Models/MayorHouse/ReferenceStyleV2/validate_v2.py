import os
root=os.path.dirname(os.path.abspath(__file__))
source=os.path.join(os.path.dirname(root),'validate_exports.py')
with open(source,encoding='utf8') as f: code=f.read()
exec(compile(code,__file__,'exec'),{'__file__':__file__,'__name__':'__main__'})
