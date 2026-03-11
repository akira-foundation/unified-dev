export interface SkillDefinition {
  id: string;
  title: string;
  description: string;
  badge?: string;
  active: boolean;
  icon: string;
  textIcon?: string;
}

export const installedSkills: SkillDefinition[] = [
  {
    id: "fortify",
    title: "Developing with Fortify",
    description: "Laravel Fortify headless authentication backend",
    badge: "audit",
    active: true,
    icon: "bg-indigo-500/10 text-indigo-500",
  },
  {
    id: "figma",
    title: "Figma",
    description: "Use Figma MCP for design-to-code work",
    active: true,
    icon: "bg-pink-500/10 text-pink-500",
  },
  {
    id: "auditor",
    title: "Default Branch Issue Auditor",
    description: "Audit default branch and open prioritized issues",
    active: true,
    icon: "bg-zinc-500/10 text-zinc-500",
  },
  {
    id: "gh-resolver",
    title: "GH Issue Resolver PR",
    description: "Triage issues by urgency, fix and open PRs",
    active: true,
    icon: "bg-zinc-500/10 text-zinc-500",
  },
  {
    id: "gh-creator",
    title: "GitHub Issue Creator",
    description: "Create concise, labeled GitHub issues",
    active: true,
    icon: "bg-zinc-500/10 text-zinc-500",
  },
  {
    id: "inertia",
    title: "Inertia React Development",
    description: "Develops Inertia.js v2 React client-side apps",
    badge: "audit",
    active: true,
    icon: "bg-purple-500/10 text-purple-500",
  },
  {
    id: "laravel-refiner",
    title: "Laravel Code Refiner",
    description: "Refine Laravel code without behavior changes",
    active: true,
    icon: "bg-red-500/10 text-red-500",
  },
  {
    id: "linear",
    title: "Linear",
    description: "Manage Linear issues in Codex",
    active: true,
    icon: "bg-zinc-800 text-white",
  },
  {
    id: "linear-creator",
    title: "Linear Issue Creator",
    description: "Create Linear issues from user requests",
    active: true,
    icon: "bg-zinc-800 text-white",
  },
  {
    id: "pest",
    title: "Pest Testing",
    description: "Tests applications using the Pest 4 PHP framework",
    badge: "audit",
    active: true,
    icon: "bg-rose-500/10 text-rose-500",
  },
  {
    id: "skill-creator",
    title: "Skill Creator",
    description: "Create or update a skill",
    active: true,
    icon: "bg-yellow-500/10 text-yellow-500",
  },
  {
    id: "skill-installer",
    title: "Skill Installer",
    description: "Install curated skills from a GitHub repo",
    active: true,
    icon: "bg-orange-500/10 text-orange-500",
  },
  {
    id: "slides",
    title: "Slides",
    description: "Create and edit slide decks with artifacts",
    active: true,
    icon: "bg-blue-500/10 text-blue-500",
  },
  {
    id: "spreadsheets",
    title: "Spreadsheets",
    description: "Create and edit spreadsheets with artifacts",
    active: true,
    icon: "bg-green-500/10 text-green-500",
  },
  {
    id: "tailwindcss",
    title: "Tailwind CSS Development",
    description: "Style applications using Tailwind CSS v4",
    badge: "audit",
    active: true,
    icon: "bg-cyan-500/10 text-cyan-500",
  },
  {
    id: "wayfinder",
    title: "Wayfinder Development",
    description: "Reference backend routes in frontend components",
    badge: "audit",
    active: true,
    icon: "bg-teal-500/10 text-teal-500",
  },
];

export interface SlashCommand {
  id: string;
  label: string;
  description: string;
  icon?: string;
}

export const slashCommands: SlashCommand[] = [
  { id: "clear", label: "/clear", description: "Clear the current conversation" },
  { id: "help",  label: "/help",  description: "Show available commands and shortcuts" },
  { id: "tree",  label: "/tree",  description: "Show the project file tree in chat" },
  { id: "diff",  label: "/diff",  description: "Show current git diff" },
  { id: "branch", label: "/branch", description: "Show current branch and status" },
];
