"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiGet, apiPost, apiPatch, apiPut } from "@/lib/api-client";
import type {
  Company,
  CompanyUpdate,
  Contract,
  ContractTemplate,
  ContractTemplateUpdate,
  SendContractResponse,
} from "@/types/api";

// --- Query keys ---

const CONTRACTS_KEY = ["contracts"] as const;
const CONTRACT_TEMPLATE_KEY = ["contract-template"] as const;

function contractKey(id: string) {
  return ["contract", id] as const;
}

function companyKey(id: string) {
  return ["company", id] as const;
}

// --- Contracts ---

export function useContracts() {
  return useQuery<Contract[]>({
    queryKey: CONTRACTS_KEY,
    queryFn: () => apiGet<Contract[]>("/api/v1/contracts"),
  });
}

export function useContract(id: string) {
  return useQuery<Contract>({
    queryKey: contractKey(id),
    queryFn: () => apiGet<Contract>(`/api/v1/contracts/${id}`),
    enabled: Boolean(id),
  });
}

/**
 * The contract (if any) generated from a given quote. Derived by listing
 * contracts and matching on quote_id — the backend has no per-quote endpoint.
 * Returns null (not undefined) once loaded with no match, so callers can
 * distinguish "loading" from "no contract yet".
 */
export function useContractForQuote(quoteId: string) {
  const query = useContracts();
  const contract =
    query.data?.find((candidate) => candidate.quote_id === quoteId) ?? null;
  return { ...query, contract };
}

export function useGenerateContract() {
  const queryClient = useQueryClient();
  return useMutation<Contract, Error, string>({
    mutationFn: (quoteId) =>
      apiPost<Contract>("/api/v1/contracts", { quote_id: quoteId }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: CONTRACTS_KEY });
    },
  });
}

export function useSendContract() {
  const queryClient = useQueryClient();
  return useMutation<SendContractResponse, Error, string>({
    mutationFn: (contractId) =>
      apiPost<SendContractResponse>(`/api/v1/contracts/${contractId}/send`, {}),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: CONTRACTS_KEY });
      queryClient.invalidateQueries({
        queryKey: contractKey(result.contract.id),
      });
    },
  });
}

// --- Contract-terms template ---

export function useContractTemplate() {
  return useQuery<ContractTemplate>({
    queryKey: CONTRACT_TEMPLATE_KEY,
    queryFn: () => apiGet<ContractTemplate>("/api/v1/contract-template"),
  });
}

export function useUpdateContractTemplate() {
  const queryClient = useQueryClient();
  return useMutation<ContractTemplate, Error, ContractTemplateUpdate>({
    mutationFn: (payload) =>
      apiPut<ContractTemplate>("/api/v1/contract-template", payload),
    onSuccess: (template) => {
      queryClient.setQueryData(CONTRACT_TEMPLATE_KEY, template);
    },
  });
}

// --- Company (license number) ---

export function useCompany(companyId: string) {
  return useQuery<Company>({
    queryKey: companyKey(companyId),
    queryFn: () => apiGet<Company>(`/api/v1/companies/${companyId}`),
    enabled: Boolean(companyId),
  });
}

export function useUpdateCompany(companyId: string) {
  const queryClient = useQueryClient();
  return useMutation<Company, Error, CompanyUpdate>({
    mutationFn: (payload) =>
      apiPatch<Company>(`/api/v1/companies/${companyId}`, payload),
    onSuccess: (company) => {
      queryClient.setQueryData(companyKey(companyId), company);
    },
  });
}
