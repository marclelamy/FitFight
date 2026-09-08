import type { ReactNode } from "react";
import localFont from "next/font/local";

import "./globals.css";

const nunito = localFont({
  src: [
    {
      path: "../../FitFight/Fonts/Nunito-Medium.ttf",
      weight: "500",
      style: "normal",
    },
    {
      path: "../../FitFight/Fonts/Nunito-Bold.ttf",
      weight: "700",
      style: "normal",
    },
    {
      path: "../../FitFight/Fonts/Nunito-ExtraBold.ttf",
      weight: "800",
      style: "normal",
    },
  ],
  variable: "--font-nunito",
});

export const metadata = {
  title: "FitFight — Challenge friends. Move to win",
  description:
    "Your step competition scorekeeper. Connect Apple Health, start a private group challenge, and see who records the most steps.",
  robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body className={nunito.variable}>{children}</body>
    </html>
  );
}
