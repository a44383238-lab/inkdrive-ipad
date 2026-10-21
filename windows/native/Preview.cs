using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

// Native Windows read-only preview. Synthetic PDF only; no library migration or AI invocation.
// It deliberately does not expose a host object or message bridge to the PLATO website.
public sealed class InkDrivePreview : Application
{
    private WebView2 browser;
    private Process ownedServer;
    private const string PreviewUrl = "http://127.0.0.1:8770/";
    [STAThread] public static void Main() { new InkDrivePreview().Start(); }
    private void Start()
    {
        var window = new Window { Title = "InkDrive 2 · Windows 검증본", Width = 1240, Height = 900, MinWidth = 860, MinHeight = 600,
            Background = new SolidColorBrush(Color.FromRgb(243,245,249)), WindowStartupLocation = WindowStartupLocation.CenterScreen };
        var layout = new DockPanel();
        var header = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(14,10,14,10) };
        var library = new Button { Content = "벡터 뷰어", Padding = new Thickness(14,7,14,7), Margin = new Thickness(0,0,8,0), IsEnabled = false };
        var plato = new Button { Content = "PLATO", Padding = new Thickness(14,7,14,7), IsEnabled = false };
        var label = new TextBlock { Text = "읽기 전용 검증본 · 실제 iPad 필기 연동 전", Margin = new Thickness(18,8,0,0), Foreground = Brushes.SlateGray };
        header.Children.Add(library); header.Children.Add(plato); header.Children.Add(label);
        DockPanel.SetDock(header, Dock.Top); layout.Children.Add(header);
        browser = new WebView2(); layout.Children.Add(browser); window.Content = layout;
        library.Click += delegate { browser.Source = new Uri(PreviewUrl); };
        plato.Click += delegate { browser.Source = new Uri("https://plato.pusan.ac.kr/"); };
        window.Loaded += async delegate {
            try {
                await EnsureServer();
                var profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "InkDrive", "WindowsPreview", "WebView2");
                var environment = await CoreWebView2Environment.CreateAsync(null, profile);
                await browser.EnsureCoreWebView2Async(environment);
                browser.CoreWebView2.Settings.IsWebMessageEnabled = false;
                browser.CoreWebView2.Settings.AreHostObjectsAllowed = false;
                browser.CoreWebView2.NewWindowRequested += delegate(object sender, CoreWebView2NewWindowRequestedEventArgs e) {
                    // Use the same dedicated profile; do not hand URLs/tokens to a shell command.
                    e.Handled = true;
                    Uri uri; if (Uri.TryCreate(e.Uri, UriKind.Absolute, out uri) && uri.Scheme == "https") browser.Source = uri;
                };
                browser.Source = new Uri(PreviewUrl); library.IsEnabled = true; plato.IsEnabled = true;
            } catch (Exception) {
                label.Text = "실행 준비 실패 · Node.js와 WebView2 Runtime을 확인해 주세요.";
            }
        };
        window.Closed += delegate { if (ownedServer != null) { try { if (!ownedServer.HasExited) ownedServer.Kill(); } catch {} ownedServer.Dispose(); } };
        Run(window);
    }
    private static async Task<bool> Healthy()
    {
        try {
            using (var client = new HttpClient { Timeout = TimeSpan.FromSeconds(1) }) {
                var text = await client.GetStringAsync(PreviewUrl + "fixture.ink.json");
                return text.Contains("\"format\":\"inkdrive.ink\"") && text.Contains("\"sourceRevision\"");
            }
        } catch { return false; }
    }
    private async Task EnsureServer()
    {
        if (await Healthy()) return;
        var server = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "windows", "reference", "server.mjs");
        if (!File.Exists(server)) throw new FileNotFoundException();
        var node = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs", "node.exe");
        if (!File.Exists(node)) node = "node.exe";
        ownedServer = Process.Start(new ProcessStartInfo(node, "\"" + server + "\"") {
            UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden, WorkingDirectory = Path.GetDirectoryName(server)
        });
        for (int i = 0; i < 30; i++) { if (await Healthy()) return; await Task.Delay(200); }
        throw new InvalidOperationException();
    }
}
