import os
source=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),'CometMinerDog','validate_dog.py')
with open(source,encoding='utf-8') as f: code=f.read()
for old,new in [('CometMinerDog','MinerChick'),('Comet Miner Dog','Miner Chick'),('Dog_','Chick_')]: code=code.replace(old,new)
exec(compile(code,__file__,'exec'),{'__file__':__file__,'__name__':'__main__'})
