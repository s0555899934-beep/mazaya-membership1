import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: 'مزايا العضوية | مجلس الجمعيات الأهلية بمنطقة الرياض', description: 'بوابة تسجيل الجمعيات وإدارة مزايا العضوية' };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ar" dir="rtl"><body>{children}</body></html>;
}
