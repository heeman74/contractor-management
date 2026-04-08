import { NextResponse } from "next/server";
import { readFile, stat } from "fs/promises";
import path from "path";

const APK_PATH = path.join(process.cwd(), "public", "releases", "contractorhub.apk");

export async function GET(): Promise<NextResponse> {
  try {
    const fileStat = await stat(APK_PATH);
    const fileBuffer = await readFile(APK_PATH);

    return new NextResponse(fileBuffer, {
      status: 200,
      headers: {
        "Content-Type": "application/vnd.android.package-archive",
        "Content-Disposition": 'attachment; filename="contractorhub.apk"',
        "Content-Length": String(fileStat.size),
        "Cache-Control": "no-cache",
      },
    });
  } catch {
    return NextResponse.json(
      { detail: "APK not available. Please contact your administrator." },
      { status: 404 }
    );
  }
}
