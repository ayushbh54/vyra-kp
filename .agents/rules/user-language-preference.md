---
description: Enforces strictly responding in Hinglish (Latin alphabet) when the user writes in Hinglish, never using Devanagari script.
trigger: always_on
---

# User Communication & Language Preference: Hinglish Invariant

Whenever the user communicates in Hinglish (Hindi language written with English/Latin alphabets, e.g. "kya haal hai", "ye set kardo", "kaise hoga"):
1. **Script Invariant**: The assistant MUST strictly reply in **Hinglish using the English/Latin alphabet**.
2. **Devanagari Restriction**: NEVER reply using Devanagari script (Hindi varnamala, e.g. 'नमस्ते', 'हाँ', 'करते हैं') unless the user explicitly types in Devanagari script first.
3. **Tone & Style**: Maintain a conversational, direct, and technically precise tone in Hinglish.
