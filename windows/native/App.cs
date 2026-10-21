using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

public sealed class InkDriveApp : Application {
    private WebView2 library,school;
    private TextBlock status;
    private Process server,ai;
    private string root="";
    private bool checking;
    private DateTime lastCheck=DateTime.MinValue;
    private string lastEvening="";
    private readonly string home=AppDomain.CurrentDomain.BaseDirectory;
    private readonly string local=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"InkDrive","Desktop");
    private const string Url="http://127.0.0.1:8771/";
    private readonly JavaScriptSerializer json=new JavaScriptSerializer { MaxJsonLength=8000000 };
    [STAThread] public static void Main(){new InkDriveApp().Start();}
    private Button Action(string name,Action action){var b=new Button{Content=name,Padding=new Thickness(13,8,13,8),Margin=new Thickness(0,0,8,0)};b.Click+=delegate{action();};return b;}
    private void Start(){
        Directory.CreateDirectory(local);try{root=File.ReadAllText(Path.Combine(local,"root.txt"));}catch{}
        var window=new Window{Title="InkDrive",Width=1280,Height=900,MinWidth=860,MinHeight=640,Background=new SolidColorBrush(Color.FromRgb(245,247,251)),WindowStartupLocation=WindowStartupLocation.CenterScreen};
        var dock=new DockPanel();var top=new WrapPanel{Margin=new Thickness(14)};
        top.Children.Add(Action("서재",()=>ShowLibrary("library")));
        top.Children.Add(Action("오늘",()=>ShowLibrary("today")));
        top.Children.Add(Action("PLATO",()=>ShowSchool("https://plato.pusan.ac.kr/")));
        top.Children.Add(Action("시간표",()=>ShowSchool("https://onestop.pusan.ac.kr/")));
        top.Children.Add(Action("지금 확인",()=>{var ignored=Check(true);}));
        top.Children.Add(Action("수업 정리",()=>{var ignored=OpenAI();}));
        top.Children.Add(Action("폴더 연결",()=>{var ignored=ChooseRoot();}));
        top.Children.Add(Action("로그아웃",()=>{if(school.CoreWebView2!=null){school.CoreWebView2.CookieManager.DeleteAllCookies();ShowSchool("https://plato.pusan.ac.kr/");status.Text="로그아웃됨";}}));
        DockPanel.SetDock(top,Dock.Top);dock.Children.Add(top);
        status=new TextBlock{Text="준비 중",Margin=new Thickness(18,8,18,12),Foreground=Brushes.SlateGray};DockPanel.SetDock(status,Dock.Bottom);dock.Children.Add(status);
        var grid=new Grid();library=new WebView2();school=new WebView2{Visibility=Visibility.Collapsed};grid.Children.Add(library);grid.Children.Add(school);dock.Children.Add(grid);window.Content=dock;
        window.Loaded+=async delegate{
            try{
                var env=await CoreWebView2Environment.CreateAsync(null,Path.Combine(local,"WebView2"));
                await library.EnsureCoreWebView2Async(env);await school.EnsureCoreWebView2Async(env);
                foreach(var view in new[]{library,school}){
                    view.CoreWebView2.Settings.AreHostObjectsAllowed=false;view.CoreWebView2.Settings.IsWebMessageEnabled=false;
                    view.CoreWebView2.NewWindowRequested+=delegate(object s,CoreWebView2NewWindowRequestedEventArgs e){e.Handled=true;Uri uri;if(Uri.TryCreate(e.Uri,UriKind.Absolute,out uri)&&Allowed(uri))school.Source=uri;};
                }
                school.CoreWebView2.NavigationStarting+=delegate(object s,CoreWebView2NavigationStartingEventArgs e){Uri uri;if(!Uri.TryCreate(e.Uri,UriKind.Absolute,out uri)||!Allowed(uri))e.Cancel=true;};
                await StartServer();ShowLibrary("library");status.Text=String.IsNullOrEmpty(root)?"폴더 연결로 InkDrive를 선택하세요.":"읽기 전용 · "+root;
                var timer=new DispatcherTimer{Interval=TimeSpan.FromMinutes(1)};
                timer.Tick+=async delegate{
                    if(DateTime.Now-lastCheck>TimeSpan.FromMinutes(30))await Check(false);
                    var seoul=TimeZoneInfo.ConvertTimeBySystemTimeZoneId(DateTime.UtcNow,"Korea Standard Time");var day=seoul.ToString("yyyy-MM-dd");
                    if(seoul.Hour>=22&&lastEvening!=day&&!String.IsNullOrEmpty(root)){lastEvening=day;RunEvening();}
                };timer.Start();
                System.Net.NetworkInformation.NetworkChange.NetworkAvailabilityChanged+=delegate(object s,System.Net.NetworkInformation.NetworkAvailabilityEventArgs e){if(e.IsAvailable)Dispatcher.BeginInvoke(new Action(()=>{lastCheck=DateTime.MinValue;var ignored=Check(false);}));};
            }catch{status.Text="Node.js와 WebView2 Runtime을 확인해 주세요.";}
        };
        window.Closed+=delegate{Stop(server);};Run(window);
    }
    private static bool Allowed(Uri uri){return uri.Scheme=="https"&&(uri.Host=="plato.pusan.ac.kr"||uri.Host=="onestop.pusan.ac.kr"||uri.Host=="login.pusan.ac.kr");}
    private void ShowLibrary(string path){school.Visibility=Visibility.Collapsed;library.Visibility=Visibility.Visible;if(library.CoreWebView2!=null)library.Source=new Uri(Url+path);}
    private void ShowSchool(string url){library.Visibility=Visibility.Collapsed;school.Visibility=Visibility.Visible;if(school.CoreWebView2!=null)school.Source=new Uri(url);}
    private static void Stop(Process p){if(p==null)return;try{if(!p.HasExited)p.Kill();}catch{}p.Dispose();}
    private string Node(){var path=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"nodejs","node.exe");return File.Exists(path)?path:"node.exe";}
    private async Task ChooseRoot(){
        using(var dialog=new System.Windows.Forms.FolderBrowserDialog{Description="iCloud Drive의 InkDrive 폴더",SelectedPath=root}){
            if(dialog.ShowDialog()!=System.Windows.Forms.DialogResult.OK)return;
            root=Path.GetFullPath(dialog.SelectedPath);File.WriteAllText(Path.Combine(local,"root.txt"),root);lastCheck=DateTime.MinValue;
        }
        Stop(server);server=null;await StartServer();ShowLibrary("library");status.Text="연결됨 · "+root;
    }
    private async Task StartServer(){
        var info=new ProcessStartInfo(Node(),"\""+Path.Combine(home,"windows","reference","server.mjs")+"\""){UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=home};
        info.EnvironmentVariables["INKDRIVE_ROOT"]=root;info.EnvironmentVariables["INKDRIVE_PORT"]="8771";info.EnvironmentVariables["INKDRIVE_CACHE"]=Path.Combine(local,"Cache");
        server=Process.Start(info);
        using(var http=new HttpClient{Timeout=TimeSpan.FromSeconds(1)})for(int i=0;i<40;i++){try{if((await http.GetAsync(Url+"library")).IsSuccessStatusCode)return;}catch{}await Task.Delay(150);}
        throw new InvalidOperationException();
    }
    private async Task Check(bool manual){
        if(checking||String.IsNullOrEmpty(root)||school.CoreWebView2==null)return;checking=true;lastCheck=DateTime.Now;status.Text="학교 확인 중";
        try{
            var cookies=new List<object>();foreach(var host in new[]{"https://plato.pusan.ac.kr/","https://onestop.pusan.ac.kr/","https://login.pusan.ac.kr/"}){
                foreach(var c in await school.CoreWebView2.CookieManager.GetCookiesAsync(host))cookies.Add(new {name=c.Name,value=c.Value,domain=c.Domain,path=c.Path,secure=c.IsSecure,httpOnly=c.IsHttpOnly,expires=c.IsSession?-1:(c.Expires.ToUniversalTime()-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalSeconds});
            }
            var deviceFile=Path.Combine(local,"device.txt");if(!File.Exists(deviceFile))File.WriteAllText(deviceFile,"windows-"+Guid.NewGuid().ToString());
            var info=new ProcessStartInfo(Node(),"\""+Path.Combine(home,"scripts","campus-worker.mjs")+"\""){UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=home};
            using(var process=Process.Start(info)){
                process.StandardInput.Write(json.Serialize(new {root=root,cookies=cookies,deviceId=File.ReadAllText(deviceFile),manual=manual}));process.StandardInput.Close();
                var output=await process.StandardOutput.ReadToEndAsync();await process.StandardError.ReadToEndAsync();await Task.Run(()=>process.WaitForExit());
                var result=json.Deserialize<Dictionary<string,object>>(output);output=null;
                if(!(bool)result["ok"]){status.Text="학교 로그인을 확인해 주세요.";return;}
                foreach(var value in (System.Collections.IEnumerable)result["cookies"]){
                    var c=(Dictionary<string,object>)value;if(!c.ContainsKey("name"))continue;
                    var cookie=school.CoreWebView2.CookieManager.CreateCookie((string)c["name"],(string)c["value"],(string)c["domain"],(string)c["path"]);
                    cookie.IsSecure=true;cookie.IsHttpOnly=c.ContainsKey("httpOnly")&&(bool)c["httpOnly"];
                    if(c.ContainsKey("expires")&&Convert.ToDouble(c["expires"])>0)cookie.Expires=new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc).AddSeconds(Convert.ToDouble(c["expires"]));
                    school.CoreWebView2.CookieManager.AddOrUpdateCookie(cookie);
                }
                status.Text="확인 완료 · "+DateTime.Now.ToString("HH:mm");
            }
        }catch{status.Text="학교 로그인·네트워크·서재 접근을 확인해 주세요.";}finally{checking=false;}
    }
    private async Task OpenAI(){
        if(String.IsNullOrEmpty(root)){status.Text="폴더를 먼저 연결하세요.";return;}
        try{
            using(var client=new HttpClient{Timeout=TimeSpan.FromSeconds(1)}){try{await client.GetStringAsync("http://127.0.0.1:8769/api/status");ShowAI();return;}catch{}}
            var info=new ProcessStartInfo(Node(),"\""+Path.Combine(home,"scripts","desktop-control.mjs")+"\""){UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=home};info.EnvironmentVariables["INKDRIVE_ROOT"]=root;ai=Process.Start(info);
            for(int i=0;i<30;i++){using(var client=new HttpClient()){try{await client.GetStringAsync("http://127.0.0.1:8769/api/status");ShowAI();return;}catch{}}await Task.Delay(200);}
        }catch{}status.Text="수업 정리 실행기를 확인해 주세요.";
    }
    private void ShowAI(){school.Visibility=Visibility.Collapsed;library.Visibility=Visibility.Visible;library.Source=new Uri("http://127.0.0.1:8769/");}
    private void RunEvening(){
        try{
            var info=new ProcessStartInfo(Node(),"\""+Path.Combine(home,"scripts","desktop-runner.mjs")+"\""){UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=home};info.EnvironmentVariables["INKDRIVE_ROOT"]=root;Process.Start(info);status.Text="밤 10시 수업 정리 시작";
        }catch{status.Text="수업 정리 실행기를 확인해 주세요.";}
    }
}
