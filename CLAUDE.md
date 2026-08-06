# Deadwire: Perimeter Trip Lines & Electric Fencing for Project Zomboid

@.claude/context.md

## SESSION START (REQUIRED)

**Before ANY work**, Claude MUST:

1. **Read context files:**
   - `.claude/context.md` - Single handoff file: state, priority, blockers, decisions
   - `.claude/rules/development-workflow.md` - How we work

2. **Check GitHub Issues:**
   ```bash
   gh issue list --state open --limit 10
   ```

3. **Output confirmation:**
   ```
   Deadwire ready. [X] open issues. Priority: [continue_with]
   Session: [N]
   Files loaded: context.md, development-workflow.md
   ```

**DO NOT skip. DO NOT begin work without this confirmation.**

---

## SESSION END (REQUIRED)

Before ending ANY session:

1. **Tasks → GitHub Issues** (incomplete work = new issue)
2. **Update context.md** (what was done, increment session, next steps)
4. **Clean workspace** (temp files, empty dirs)
5. **Commit and push**
6. **Tell user:** `Continue with [next priority]`

---

## TODO = GITHUB ISSUE

When user says "todo", "add to backlog", "remember to", or similar:
- Do NOT use internal todo tracking for persistent tasks
- Create a GitHub Issue immediately
- Confirm: "Created Issue #XX: [title]"

---

## BEFORE CODING (REQUIRED)

When user requests code changes, Claude MUST:

1. **Read the implementation plan:**
   ```
   docs/IMPLEMENTATION-PLAN.md
   ```

2. **Read relevant rules:**
   ```
   .claude/rules/development-workflow.md
   ```

3. **Output confirmation:**
   ```
   Ready to implement: [brief description]
   ```

---

## PROJECT ARCHITECTURE

Three-tier Lua design:

```
Client (UI, menus)  →  sendClientCommand("Deadwire", cmd, args)
                           ↓
Server (validation)  →  OnClientCommand handler validates + executes
                           ↓
Server (broadcast)   →  sendServerCommand("Deadwire", cmd, args)
                           ↓
Client (effects)     →  OnServerCommand plays sounds, updates UI
```

**Shared** code (WireNetwork, Config) runs on both client and server.

---

## MOD SYNC (REQUIRED)

After **every** code change, sync to PZ mods folder:

```bash
cp -r "c:/xampp/htdocs/deadwire/Contents/mods/Deadwire/"* "C:/Users/roban/Zomboid/mods/Deadwire/"
```

Do NOT wait for the user to ask.

---

## REFERENCE FILES

| File | Purpose | When to Read |
|------|---------|--------------|
| `.claude/context.md` | Project state, priority, blockers | Session start |
| `.claude/rules/development-workflow.md` | How we work | Session start |
| `docs/DESIGN.md` | Game design document | Understanding features |
| `docs/IMPLEMENTATION-PLAN.md` | Technical plan with code | Before coding |

---

## PRIVACY FIRST

- No PII or credentials in commits
- No sensitive data in context files
