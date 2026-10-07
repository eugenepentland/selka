import subprocess,sys,time,os
p=subprocess.Popen([sys.executable,'-c',"import subprocess,sys,time,os\np=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)'],start_new_session=True)\nos.write(2,('grandchild=%d\\n'%p.pid).encode())\ntime.sleep(30)\n"],start_new_session=True)
os.write(1,b'partial\xff\n')
os.write(2,('child=%d\n'%p.pid).encode())
time.sleep(30)
