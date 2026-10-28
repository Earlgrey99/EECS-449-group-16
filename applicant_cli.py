"""Jac CLI to Python feature bridge."""
import json,sys
from pathlib import Path
from applicant_profile import load_profile,update_profile
from application_autofill import browser_autofill,read_mapping
from resume_tailoring import read_resume,generate_tailored_markdown,export_tailoring
def profile_command(args):
    profile=update_profile(args.set_fields,args.file) if args.set_fields else load_profile(args.file)
    if args.show or not args.set_fields:print(json.dumps(profile,indent=2))
    else:print("Applicant profile updated.")
    return 0
def autofill_command(args):
    profile=load_profile(args.profile)
    if not profile:raise ValueError("Save a profile first with 'profile --set'")
    result=browser_autofill(args.target,profile,read_mapping(args.mapping),args.apply,args.headless,args.hold_seconds)
    print(json.dumps(result,indent=2))
    print("Application NOT submitted; final review and submission are manual.")
    return 0
def tailor_command(args):
    profile=load_profile(args.profile)
    path=args.resume or profile.get("resume_path")
    if not path:raise ValueError("Provide --resume or set resume_path in your profile")
    description=Path(args.job_description).read_text(encoding="utf8") if args.job_description else args.job_text
    if not description:raise ValueError("Provide --job-description or --job-text")
    markdown,report=generate_tailored_markdown(read_resume(path),description,args.role)
    output=export_tailoring(markdown,args.output)
    output.with_suffix(".review.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf8")
    print("Saved review to",output,"- original resume unchanged")
    return 0
