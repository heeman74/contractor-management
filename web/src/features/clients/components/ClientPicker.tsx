"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, UserPlus } from "lucide-react";

import { Input } from "@/components/ui/input";
import { apiGet, apiPost } from "@/lib/api-client";
import type { ClientListItem } from "@/types/api";

/**
 * Pick the client a quote is for, or add one that does not exist yet.
 *
 * A quote cannot be sent without a client — the backend refuses the transition —
 * so this is where that requirement gets satisfied rather than discovered at the
 * point of sending.
 */

export interface ClientPickerProps {
  value: string | null;
  onChange: (clientId: string | null, label: string | null) => void;
}

function clientLabel(client: ClientListItem): string {
  const name = [client.first_name, client.last_name].filter(Boolean).join(" ").trim();
  return name || client.email;
}

export function ClientPicker({ value, onChange }: ClientPickerProps) {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [creating, setCreating] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [newFirstName, setNewFirstName] = useState("");
  const [newLastName, setNewLastName] = useState("");
  const [error, setError] = useState<string | null>(null);

  const { data: clients, isLoading } = useQuery<ClientListItem[]>({
    queryKey: ["clients", search],
    queryFn: () =>
      apiGet<ClientListItem[]>(
        `/api/v1/crm/clients?${new URLSearchParams(search ? { search } : {})}`
      ),
  });

  const createClient = useMutation({
    mutationFn: (body: { email: string; first_name?: string; last_name?: string }) =>
      apiPost<ClientListItem>("/api/v1/crm/clients", body),
    onSuccess: (created) => {
      void queryClient.invalidateQueries({ queryKey: ["clients"] });
      onChange(created.user_id, clientLabel(created));
      setCreating(false);
      setNewEmail("");
      setNewFirstName("");
      setNewLastName("");
      setError(null);
    },
    onError: (err: unknown) => {
      const detail =
        err && typeof err === "object" && "detail" in err
          ? String((err as { detail: unknown }).detail)
          : "Could not add that client.";
      setError(detail);
    },
  });

  if (creating) {
    return (
      <div className="space-y-2">
        <p className="text-xs font-medium text-gray-700">New client</p>
        <Input
          aria-label="Client email"
          placeholder="email@example.com"
          value={newEmail}
          onChange={(event) => setNewEmail(event.target.value)}
        />
        <div className="flex gap-2">
          <Input
            aria-label="Client first name"
            placeholder="First name"
            value={newFirstName}
            onChange={(event) => setNewFirstName(event.target.value)}
          />
          <Input
            aria-label="Client last name"
            placeholder="Last name"
            value={newLastName}
            onChange={(event) => setNewLastName(event.target.value)}
          />
        </div>
        {error ? (
          <p role="alert" className="text-xs text-red-600">
            {error}
          </p>
        ) : null}
        <p className="text-xs text-gray-500">
          Adding a client does not give them a login.
        </p>
        <div className="flex gap-2">
          <button
            type="button"
            disabled={!newEmail.trim() || createClient.isPending}
            onClick={() =>
              createClient.mutate({
                email: newEmail.trim(),
                first_name: newFirstName.trim() || undefined,
                last_name: newLastName.trim() || undefined,
              })
            }
            className="inline-flex h-8 items-center gap-1.5 rounded-lg bg-brand px-3 text-xs font-medium text-brand-foreground disabled:opacity-50"
          >
            {createClient.isPending ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden />
            ) : null}
            Add client
          </button>
          <button
            type="button"
            onClick={() => {
              setCreating(false);
              setError(null);
            }}
            className="h-8 rounded-lg border border-gray-300 px-3 text-xs text-gray-700"
          >
            Cancel
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <Input
        aria-label="Search clients"
        placeholder="Search clients…"
        value={search}
        onChange={(event) => setSearch(event.target.value)}
      />
      <div className="max-h-40 overflow-y-auto rounded-lg border border-gray-200">
        {isLoading ? (
          <p className="p-2 text-xs text-gray-500">Loading clients…</p>
        ) : !clients?.length ? (
          <p className="p-2 text-xs text-gray-500">No clients yet.</p>
        ) : (
          <ul>
            {clients.map((client) => (
              <li key={client.user_id}>
                <button
                  type="button"
                  onClick={() => onChange(client.user_id, clientLabel(client))}
                  aria-pressed={value === client.user_id}
                  className={
                    value === client.user_id
                      ? "w-full px-2 py-1.5 text-left text-xs font-medium text-brand"
                      : "w-full px-2 py-1.5 text-left text-xs text-gray-800 hover:bg-gray-50"
                  }
                >
                  {clientLabel(client)}
                  <span className="ml-1 text-gray-500">{client.email}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      <button
        type="button"
        onClick={() => setCreating(true)}
        className="inline-flex items-center gap-1.5 text-xs font-medium text-brand"
      >
        <UserPlus className="h-3.5 w-3.5" aria-hidden />
        Add a new client
      </button>
    </div>
  );
}
