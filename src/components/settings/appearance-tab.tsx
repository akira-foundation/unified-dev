import { useToggle } from "@uidotdev/usehooks";
import { Palette } from "lucide-react";
import { useI18n } from "@/i18n/i18n";
import { useSettingsStore } from "@/stores/settings-store";
import { useAppearance } from "@/hooks/use-appearance";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import {
  vscDarkPlus,
  atomDark,
  dracula,
  nord,
  oneDark,
  coldarkDark,
  oneLight,
  ghcolors,
  nightOwl,
  materialDark,
  materialOceanic,
  synthwave84,
  shadesOfPurple,
  duotoneDark,
  gruvboxDark,
} from "react-syntax-highlighter/dist/esm/styles/prism";
import { SettingsSection } from "./settings-section";
import { SettingsItem } from "./settings-item";

const CODE_THEMES: Record<string, any> = {
  vscDarkPlus,
  atomDark,
  dracula,
  nord,
  oneDark,
  coldarkDark,
  oneLight,
  ghcolors,
  nightOwl,
  materialDark,
  materialOceanic,
  synthwave84,
  shadesOfPurple,
  duotoneDark,
  gruvboxDark,
};

const SAMPLE_CODE = `<?php

namespace App\\Actions;

final readonly class CreateUserAction
{
    public function handle(array $data): User
    {
        return User::create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => bcrypt($data['password']),
        ]);
    }
}`;

export function AppearanceTab() {
  const { t } = useI18n();
  const { editorTheme, setEditorTheme, diffSyntaxHighlight, setDiffSyntaxHighlight } = useSettingsStore();
  const { appearance, updateAppearance } = useAppearance();
  const [showThemePreview, toggleShowThemePreview] = useToggle(false);

  return (
    <div className="animate-in fade-in duration-300">
      <SettingsSection
        title={t("settings.appearance.section.title")}
        description={t("settings.general.appearanceDesc")}
        icon={Palette}
      >
        <SettingsItem
          label={t("settings.appearance.syncWithSystem")}
          description={t("settings.appearance.syncWithSystem.desc")}
          action={
            <Switch
              checked={appearance === "system"}
              onCheckedChange={(checked) => updateAppearance(checked ? "system" : "dark")}
            />
          }
        />
        <SettingsItem
          label={t("settings.appearance.theme")}
          description={t("settings.appearance.theme.desc")}
          action={
            <Select
              value={appearance === "system" ? "dark" : appearance}
              onValueChange={(value) => updateAppearance(value as "light" | "dark")}
              disabled={appearance === "system"}
            >
              <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300 disabled:opacity-50 disabled:cursor-not-allowed">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="dark">{t("settings.appearance.themeDark")}</SelectItem>
                <SelectItem value="light">{t("settings.appearance.themeLight")}</SelectItem>
              </SelectContent>
            </Select>
          }
        />
        <SettingsItem
          label={t("settings.appearance.diffHighlight")}
          description={t("settings.appearance.diffHighlight.desc")}
          action={
            <Switch
              checked={diffSyntaxHighlight}
              onCheckedChange={setDiffSyntaxHighlight}
            />
          }
        />
        <SettingsItem
          label={t("settings.appearance.codeTheme")}
          description={t("settings.appearance.codeTheme.desc")}
          action={
            <div className="flex items-center gap-2">
              <Button
                variant="outline"
                size="sm"
                className="h-8 text-[11px] font-bold uppercase tracking-wider"
                onClick={() => toggleShowThemePreview()}
              >
                {showThemePreview ? t("settings.appearance.preview.hide") : t("settings.appearance.preview.show")}
              </Button>
              <Select value={editorTheme} onValueChange={setEditorTheme}>
                <SelectTrigger className="w-40 h-8 rounded-md border-zinc-200 bg-zinc-100 px-3 text-xs font-medium text-zinc-600 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="oneDark">One Dark</SelectItem>
                  <SelectItem value="vscDarkPlus">VS Code Dark</SelectItem>
                  <SelectItem value="nightOwl">Night Owl</SelectItem>
                  <SelectItem value="materialDark">Material Dark</SelectItem>
                  <SelectItem value="materialOceanic">Material Oceanic</SelectItem>
                  <SelectItem value="synthwave84">Synthwave '84</SelectItem>
                  <SelectItem value="shadesOfPurple">Shades of Purple</SelectItem>
                  <SelectItem value="dracula">Dracula</SelectItem>
                  <SelectItem value="nord">Nord</SelectItem>
                  <SelectItem value="atomDark">Atom Dark</SelectItem>
                  <SelectItem value="coldarkDark">Coldark</SelectItem>
                  <SelectItem value="gruvboxDark">Gruvbox Dark</SelectItem>
                  <SelectItem value="duotoneDark">Duotone Dark</SelectItem>
                  <SelectItem value="oneLight">One Light</SelectItem>
                  <SelectItem value="ghcolors">GitHub</SelectItem>
                </SelectContent>
              </Select>
            </div>
          }
        />

        {showThemePreview && (
          <div className="px-6 py-4 animate-in fade-in slide-in-from-top-2 duration-300">
            <div className="rounded-xl border border-zinc-200 dark:border-white/5 overflow-hidden bg-[#0A0A0A] shadow-2xl">
              <div className="bg-[#0D0D0D] px-4 py-2.5 border-b border-white/5 flex justify-between items-center bg-gradient-to-r from-[#0D0D0D] to-[#111111]">
                <div className="flex items-center gap-2">
                  <div className="flex gap-1.5">
                    <div className="w-2.5 h-2.5 rounded-full bg-red-500/20 border border-red-500/40" />
                    <div className="w-2.5 h-2.5 rounded-full bg-amber-500/20 border border-amber-500/40" />
                    <div className="w-2.5 h-2.5 rounded-full bg-emerald-500/20 border border-emerald-500/40" />
                  </div>
                  <span className="text-[10px] uppercase tracking-widest font-bold text-zinc-500 ml-2">Preview: CreateUserAction.php</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="text-[9px] font-mono text-zinc-600 bg-white/5 px-1.5 py-0.5 rounded">PHP 8.4</span>
                </div>
              </div>
              <div className="p-0 max-h-[350px] overflow-auto custom-scrollbar bg-transparent">
                <SyntaxHighlighter
                  language="php"
                  style={CODE_THEMES[editorTheme] || oneDark}
                  showLineNumbers={true}
                  lineNumberStyle={{
                    minWidth: "3.5em",
                    paddingRight: "1.5em",
                    color: "#3f3f3f",
                    textAlign: "right",
                    fontSize: "11px",
                    userSelect: "none",
                    opacity: 0.5,
                  }}
                  codeTagProps={{ style: { background: "none" } }}
                  customStyle={{
                    margin: 0,
                    padding: "1.5rem 0",
                    background: "transparent",
                    fontSize: "13px",
                    fontFamily: "JetBrains Mono, Menlo, Monaco, Consolas, monospace",
                    lineHeight: "1.7",
                  }}
                >
                  {SAMPLE_CODE}
                </SyntaxHighlighter>
              </div>
            </div>
          </div>
        )}

      </SettingsSection>
    </div>
  );
}
