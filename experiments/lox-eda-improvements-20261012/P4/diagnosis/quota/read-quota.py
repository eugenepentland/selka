#!/usr/bin/env python3
"""Read-only Linux x86_64 query of this user's /tmp quota and filesystem state."""
import ctypes,datetime,os,platform,json,subprocess
assert platform.system()=='Linux' and platform.machine()=='x86_64'
class Dqblk(ctypes.Structure):
    _fields_=[(name,ctypes.c_uint64) for name in ['bhardlimit','bsoftlimit','curspace','ihardlimit','isoftlimit','curinodes','btime','itime']]+[('valid',ctypes.c_uint32)]
lib=ctypes.CDLL(None,use_errno=True)
lib.syscall.restype=ctypes.c_long
fd=os.open('/tmp',os.O_RDONLY|os.O_DIRECTORY)
quota=Dqblk()
try:
    # __NR_quotactl_fd=443; QCMD(Q_GETQUOTA=0x800007, USRQUOTA=0).
    result=lib.syscall(ctypes.c_long(443),ctypes.c_uint(fd),ctypes.c_uint(0x80000700),ctypes.c_uint(os.getuid()),ctypes.byref(quota))
    err=ctypes.get_errno()
finally:
    os.close(fd)
assert result==0,(result,err)
values={name:getattr(quota,name) for name,_ in quota._fields_}
fs=os.statvfs('/tmp')
print(json.dumps({'timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'uid':os.getuid(),'query':'quotactl_fd(fd(/tmp,O_RDONLY|O_DIRECTORY), QCMD(Q_GETQUOTA,USRQUOTA), getuid(), if_dqblk)','syscall_number':443,'command':0x80000700,'return':result,'errno':err,'quota':values,'quota_limit_units':'bhardlimit/bsoftlimit in1024-byte blocks; curspace inbytes; inode fields incounts','hard_limit_bytes':quota.bhardlimit*1024,'soft_limit_bytes':quota.bsoftlimit*1024,'usage_bytes':quota.curspace,'hard_limit_headroom_bytes':quota.bhardlimit*1024-quota.curspace,'filesystem_available_bytes':fs.f_bavail*fs.f_frsize,'filesystem_free_inodes':fs.f_favail,'mount':subprocess.check_output(['findmnt','-no','SOURCE,FSTYPE,OPTIONS','/tmp'],text=True).strip()},indent=2))
