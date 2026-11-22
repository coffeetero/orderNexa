/**
 * Cookie remembering whether the docked sidebar is hidden. Lives in a plain module (not a 'use client' file) so
 * the server layout can read it and the client shell can write it with the same name.
 */
export const SIDEBAR_COOKIE = 'bps_sidebar';
export const SIDEBAR_COLLAPSED = 'collapsed';
export const SIDEBAR_OPEN = 'open';
