"use client";

import { useId, useRef, useState } from "react";

import type { IosInstall } from "@/lib/types/app/ios-install";

export function TestflightInvite({
  label,
  kind,
  install,
}: {
  label: string;
  kind: "header" | "hero";
  install: IosInstall;
}) {
  const titleId = useId();
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [open, setOpen] = useState(false);
  let eyebrow: string;
  let title: string;
  let body: string;
  let action: string;
  switch (install.channel) {
    case "testflight":
      eyebrow = "BETA ON TESTFLIGHT";
      title = "Get FitFight on your iPhone";
      body =
        "FitFight isn't on the App Store yet. Apple uses TestFlight to install beta iPhone apps. Open this on your iPhone.";
      action = "Open TestFlight";
      break;
    case "appStore":
      eyebrow = "ON THE APP STORE";
      title = "Get FitFight on your iPhone";
      body = "Download FitFight from the App Store, then open a shared fight link on this iPhone.";
      action = "Open App Store";
      break;
    default: {
      const _exhaustive: never = install.channel;
      return _exhaustive;
    }
  }

  return (
    <>
      <button
        type="button"
        className={kind === "header" ? "header-action" : "primary-action"}
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => {
          dialogRef.current?.showModal();
          setOpen(true);
        }}
      >
        {label}
      </button>
      <dialog
        ref={dialogRef}
        className="testflight-dialog"
        aria-labelledby={titleId}
        onClose={() => setOpen(false)}
        onClick={(event) => {
          if (event.target === event.currentTarget) {
            event.currentTarget.close();
          }
        }}
      >
        <p className="eyebrow">{eyebrow}</p>
        <h2 id={titleId}>{title}</h2>
        <p>{body}</p>
        <a className="primary-action" href={install.url} rel="noopener noreferrer">
          {action}
        </a>
        <button
          type="button"
          className="dialog-dismiss"
          onClick={() => dialogRef.current?.close()}
        >
          Not now
        </button>
      </dialog>
    </>
  );
}
