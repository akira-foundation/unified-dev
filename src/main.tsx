import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { initializeTheme } from "./hooks/use-appearance";
import { I18nProvider } from "./i18n/i18n";
import "./App.css";

initializeTheme();

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <I18nProvider>
      <App />
    </I18nProvider>
  </React.StrictMode>,
);
