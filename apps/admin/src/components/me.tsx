"use client";

import { createContext, ReactNode, useContext, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Area, Me, TeamMember, canUse } from "@/lib/team";

const MeContext = createContext<Me | null>(null);

export function MeProvider({ me, children }: { me: Me; children: ReactNode }) {
  return <MeContext.Provider value={me}>{children}</MeContext.Provider>;
}

/** The signed-in team member. */
export function useMe(): Me | null {
  return useContext(MeContext);
}

/** Can the signed-in team member use [area]? */
export function useCan(area: Area | "owner"): boolean {
  return canUse(useMe(), area);
}

/** Everyone on the team (removed members too), for names and "assigned to". */
export function useTeam(): TeamMember[] {
  const [team, setTeam] = useState<TeamMember[]>([]);
  useEffect(() => {
    createClient()
      .rpc("admin_team_list")
      .then(({ data }) => setTeam((data as TeamMember[]) ?? []));
  }, []);
  return team;
}

export const memberName = (team: TeamMember[], id: string | null | undefined) => {
  if (!id) return null;
  const m = team.find((t) => t.id === id);
  return m ? m.name || m.email : null;
};
