"""Local applicant profile validation and private storage."""
import json, os, re
from pathlib import Path
DEFAULT_PATH=Path.home()/".eecs449"/"profile.json"
FIELDS={"name","email","phone","location","address","linkedin","github","portfolio","skills","education","experience","resume_path","first_name","last_name"}
def path_for(path=None):
    return Path(path).expanduser() if path else DEFAULT_PATH
def validate_field(key,value):
    if key not in FIELDS: raise ValueError("Unknown profile field: "+key)
    if not isinstance(value,str): raise ValueError("Profile values must be strings")
    value=value.strip()
    if key=="email" and value and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+",value): raise ValueError("Invalid email")
    if key=="phone" and value and not re.fullmatch(r"[+\d\s()\-.]{7,25}",value): raise ValueError("Invalid phone number")
    if key in ("linkedin","github","portfolio") and value and not re.match(r"^https?://[^\s.]+\.[^\s]+$",value): raise ValueError("Invalid URL")
    return value
def load_profile(path=None):
    file=path_for(path)
    if not file.exists(): return {}
    obj=json.loads(file.read_text(encoding="utf8"))
    if not isinstance(obj,dict): raise ValueError("Invalid profile structure")
    return {k:validate_field(k,v) for k,v in obj.items()}
def save_profile(profile,path=None):
    file=path_for(path); file.parent.mkdir(parents=True,exist_ok=True)
    data={k:validate_field(k,v) for k,v in profile.items()}
    fd=os.open(str(file),os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    try:
        os.fchmod(fd,0o600)
        with os.fdopen(fd,"w",encoding="utf8") as f: json.dump(data,f,indent=2,ensure_ascii=False);f.write("\n")
    except BaseException: os.close(fd) if fd>=0 else None;raise
    return data
def update_profile(pairs,path=None):
    data=load_profile(path)
    for k,v in pairs: data[k]=validate_field(k,v)
    return save_profile(data,path)
