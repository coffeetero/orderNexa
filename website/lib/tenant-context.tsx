'use client';

import { createContext, useContext, useState } from 'react';

interface TenantContextValue {
  tenant_id: number;
  setTenantId: (id: number) => void;
}

const TenantContext = createContext<TenantContextValue>({
  tenant_id: 1,
  setTenantId: () => {},
});

export function TenantProvider({ children }: { children: React.ReactNode }) {
  const [tenant_id, setTenantId] = useState(1);
  return (
    <TenantContext.Provider value={{ tenant_id, setTenantId }}>
      {children}
    </TenantContext.Provider>
  );
}

export function useTenant() {
  return useContext(TenantContext);
}
