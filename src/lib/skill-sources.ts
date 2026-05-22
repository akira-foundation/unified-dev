export interface RemoteSkill {
  uid: string;
  id: string;
  name: string;
  description: string;
  repo_url: string;
  installs: number;
}

export interface SkillSource {
  id: string;
  name: string;
  description: string;
  type: "remote";
  repoUrl?: string;
  branch?: string;
}

export const SKILL_SOURCES: SkillSource[] = [
  {
    id: "skills-sh",
    name: "skills.sh",
    description: "Community skill registry",
    type: "remote",
  },
  {
    id: "claude",
    name: "Claude",
    description: "alirezarezvani/claude-skills",
    type: "remote",
    repoUrl: "https://github.com/alirezarezvani/claude-skills",
    branch: "main",
  },
  {
    id: "codex",
    name: "Codex",
    description: "ComposioHQ/awesome-codex-skills",
    type: "remote",
    repoUrl: "https://github.com/ComposioHQ/awesome-codex-skills",
    branch: "master",
  },
];
