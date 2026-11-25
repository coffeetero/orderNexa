import { PortalUsers } from '@/components/features/customer/PortalUsers';

export const metadata = { title: 'Users' };

/** Customer portal › Users (customer administrators). The API and database refuse anyone without Users access. */
export default function PortalUsersPage() {
  return <PortalUsers />;
}
