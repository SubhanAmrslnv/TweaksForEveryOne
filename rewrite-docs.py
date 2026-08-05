import re

with open('docs/TASKBAR-AND-INTERNALS.md', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update the Taskbar Height section
taskbar_section_regex = r'## Taskbar height — what is actually possible.*?---'
new_taskbar_section = '''## Taskbar management

The Windows 11 taskbar cannot be meaningfully shrunk by an ordinary program. 
Because of this, Window Tweaks now integrates directly with **ExplorerPatcher** to achieve a small, responsive taskbar.

The installer automatically fetches the latest `ep_setup.exe` from GitHub and installs it with administrator privileges.
Once installed, Window Tweaks provides a UI to switch between the Windows 10 style taskbar (which supports small icons) and the Windows 11 style.

The old method of manually cropping the taskbar (using `TaskbarCore.ahk`) has been completely removed as it was fundamentally broken on modern builds of Windows 11.

---'''
content = re.sub(taskbar_section_regex, new_taskbar_section, content, flags=re.DOTALL)

# 2. Update the "Files" table to remove TaskbarCore.ahk
content = re.sub(r'\| `TaskbarCore\.ahk` \| Taskbar height engine \|\n', '', content)

with open('docs/TASKBAR-AND-INTERNALS.md', 'w', encoding='utf-8') as f:
    f.write(content)
print("Done")
