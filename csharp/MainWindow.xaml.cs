using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace WindowTweaks
{
    public partial class MainWindow : Window
    {
        public MainWindow()
        {
            InitializeComponent();
        }

        private void SidebarList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (SidebarList.SelectedItem is ListBoxItem selectedItem)
            {
                string tag = selectedItem.Tag?.ToString();
                MainContent.Content = BuildPage(tag);
            }
        }

        private UIElement BuildPage(string pageTag)
        {
            StackPanel panel = new StackPanel();

            Style headerStyle = (Style)FindResource("HeaderStyle");
            Style subHeaderStyle = (Style)FindResource("SubHeaderStyle");
            Style toggleStyle = (Style)FindResource("ToggleSwitchStyle");
            Style descStyle = (Style)FindResource("DescriptionStyle");

            switch (pageTag)
            {
                case "WindowManagement":
                    panel.Children.Add(new TextBlock { Text = "Window Management", Style = headerStyle });
                    
                    panel.Children.Add(new TextBlock { Text = "Movement & Dragging", Style = subHeaderStyle });
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Linux-Style Alt-Drag (Move & Resize)", "Alt+Left Click to move any window. Alt+Right Click to resize.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Magnetic Window Snapping", "Windows magnetically snap to edges and other windows when thrown.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Magnetic Window Groups", "Hold Shift while moving to move adjacent windows together.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Middle-Click Titlebar to Close", "Quickly close windows like browser tabs.", true));

                    panel.Children.Add(new TextBlock { Text = "Layout & States", Style = subHeaderStyle });
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Position Memory", "Apps reopen exactly where you left them.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Window Roll-Up", "Scroll on a titlebar to shade/unshade the window.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Minimize to Tray", "Shift+Alt+H hides apps to the system tray instead of taskbar.", true));
                    break;

                case "PowerFeatures":
                    panel.Children.Add(new TextBlock { Text = "Power Features", Style = headerStyle });
                    
                    panel.Children.Add(new TextBlock { Text = "Workflow", Style = subHeaderStyle });
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Plain Text Paste (Ctrl+Alt+V)", "Strips formatting from the clipboard before pasting.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Quick Folder Jump (Ctrl+G)", "Jumps File Dialogs to your last active Explorer folder.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "macOS Quick Look (Shift+Alt+Q)", "Instantly preview files in Explorer without opening apps.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Minimalist Spotlight Search", "Double tap Ctrl to open the quick launcher.", true));
                    
                    panel.Children.Add(new TextBlock { Text = "System", Style = subHeaderStyle });
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Global Microphone Mute", "Double tap Alt to toggle mute globally.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Smart Auto-hide Taskbar", "Taskbar only hides when a window intersects it.", false));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Stealth Panic Mode", "Press Esc 3 times to hide all visible windows immediately.", true));
                    break;

                case "Animation":
                    panel.Children.Add(new TextBlock { Text = "Animation & Physics", Style = headerStyle });
                    
                    panel.Children.Add(new TextBlock { Text = "Window Closing", Style = subHeaderStyle });
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Gravity Drop Close (Alt+F4)", "Windows fall off the screen obeying gravity.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Shatter Close (Shift+Alt+F4)", "Windows shatter into 3D glass pieces.", true));

                    panel.Children.Add(new TextBlock { Text = "Motion", Style = subHeaderStyle });
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Elastic Drag & Throw", "Windows carry momentum when thrown across the screen.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Parallax Dragging", "Windows become transparent proportionally to drag speed.", true));
                    break;
                
                case "HotCorners":
                    panel.Children.Add(new TextBlock { Text = "Hot Corners", Style = headerStyle });
                    panel.Children.Add(new TextBlock { Text = "macOS-style screen corner triggers.", Style = descStyle, Margin = new Thickness(0, 0, 0, 20) });
                    
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Enable Hot Corners", "Activate actions by throwing your mouse into screen corners.", true));
                    break;
                    
                case "General":
                    panel.Children.Add(new TextBlock { Text = "General Settings", Style = headerStyle });
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Start with Windows", "Launch Window Tweaks automatically on login.", true));
                    panel.Children.Add(CreateSetting(toggleStyle, descStyle, "Game Mode Disable", "Automatically suspend hooks while full-screen games are running.", true));
                    break;

                default:
                    panel.Children.Add(new TextBlock { Text = "Select a category on the left.", Style = subHeaderStyle });
                    break;
            }

            return panel;
        }

        private UIElement CreateSetting(Style toggleStyle, Style descStyle, string title, string description, bool isChecked)
        {
            StackPanel panel = new StackPanel();
            System.Windows.Controls.CheckBox cb = new System.Windows.Controls.CheckBox 
            { 
                Content = title, 
                Style = toggleStyle, 
                IsChecked = isChecked 
            };
            
            TextBlock desc = new TextBlock 
            { 
                Text = description, 
                Style = descStyle 
            };

            panel.Children.Add(cb);
            panel.Children.Add(desc);
            return panel;
        }
    }
}