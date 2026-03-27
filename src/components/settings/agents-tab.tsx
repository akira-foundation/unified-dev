import { Bot } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { SettingsSection } from "./settings-section";
import { SettingsTextarea } from "./settings-textarea";

export function AgentsTab() {
  const { t } = useI18n();

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection title={t("settings.agents.title")} description={t("settings.agents.description")} icon={Bot}>
        <SettingsTextarea
          label={t("settings.agents.envVars.label")}
          description={t("settings.agents.envVars.description")}
          defaultValue={`ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_CODE_USE_BEDROCK=1
AWS_REGION=us-east-1
AWS_PROFILE=default`}
        />
      </SettingsSection>
    </div>
  );
}
