import type { ThreadMember } from "../hooks/useMessageInput";

interface MentionSuggestionsProps {
  suggestions: ThreadMember[];
  onSelect: (member: ThreadMember) => void;
}

export function MentionSuggestions({
  suggestions,
  onSelect,
}: MentionSuggestionsProps) {
  return (
    <div className="absolute bottom-full left-0 right-0 z-50 mb-1 max-h-48 overflow-y-auto rounded-md border bg-popover shadow-md">
      <ul role="listbox" aria-label="Mention suggestions">
        {suggestions.map((member) => (
          <li key={member.user_id}>
            <button
              type="button"
              className="w-full px-3 py-2 text-left text-sm hover:bg-muted focus:bg-muted focus:outline-none"
              onMouseDown={(e) => {
                e.preventDefault(); // prevent textarea blur
                onSelect(member);
              }}
            >
              @{member.name}
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
