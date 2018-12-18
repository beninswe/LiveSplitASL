state("retroarch", "32bit") {}
state("retroarch", "64bit") {}
state("Fusion") {}
state("gens") {}
state("blastem") {}
state("SEGAGameRoom") {}
state("SEGAGenesisClassics") {}

startup
{
    vars.timerModel = new TimerModel { CurrentState = timer };
    settings.Add("actsplit", false, "Split on each Act");
    settings.SetToolTip("actsplit", "If unchecked, will only split at the end of each Zone.");
    
    settings.Add("act_mg1", false, "Ignore Marble Garden 1", "actsplit");
    settings.Add("act_ic1", false, "Ignore Ice Cap 1", "actsplit");
    settings.Add("act_lb1", false, "Ignore Launch Base 1", "actsplit");

    settings.Add("hard_reset", true, "Reset timer on Hard Reset?");
    
    settings.SetToolTip("act_mg1", "If checked, will not split the end of the first Act. Use if you have per act splits generally but not for this zone.");
    settings.SetToolTip("act_ic1", "If checked, will not split the end of the first Act. Use if you have per act splits generally but not for this zone.");
    settings.SetToolTip("act_lb1", "If checked, will not split the end of the first Act. Use if you have per act splits generally but not for this zone.");

    settings.SetToolTip("hard_reset", "If checked, a hard reset will reset the timer.");

    Action<string> DebugOutput = (text) => {
        print("[S3K Autosplitter] "+text);
    };

    Action<ExpandoObject> DebugOutputExpando = (ExpandoObject dynamicObject) => {
            var dynamicDictionary = dynamicObject as IDictionary<string, object>;
         
            foreach(KeyValuePair<string, object> property in dynamicDictionary)
            {
                print(String.Format("[S3K Autosplitter] {0}: {1}", property.Key, property.Value.ToString()));
            }
            print("");
    };

    Func<ushort,ushort> SwapEndianness = (ushort value) => {
        var b1 = (value >> 0) & 0xff;
        var b2 = (value >> 8) & 0xff;

        return (ushort) (b1 << 8 | b2 << 0);
    };
    vars.SwapEndianness = SwapEndianness;
    vars.DebugOutput = DebugOutput;
    vars.DebugOutputExpando = DebugOutputExpando;
    refreshRate = 60;
}

init
{
    vars.bonus = false;
    vars.stopwatch = new Stopwatch();
    vars.nextzone = 0;
    vars.nextact = 1;
    vars.dez2split = false;
    vars.ddzsplit = false;
    vars.sszsplit = false; //boss is defeated twice
    vars.savefile = 255;
    vars.processingzone = false;
    vars.skipsAct1Split = false;
    vars.gameshortname = "";
    vars.specialstagetimer = new Stopwatch();
    vars.addspecialstagetime = false;
    vars.specialstagetimeadded = false;
    vars.gotEmerald = false;
    vars.chaoscatchall = false;
    if ( game.ProcessName == "retroarch" ) {
        if ( game.Is64Bit() ) {
            version = "64bit";
        } else {
            version = "32bit";
        }
    }
    vars.nextzonemap = false;


    long memoryOffset;
    IntPtr baseAddress;
    long genOffset = 0;
    baseAddress = modules.First().BaseAddress;
    bool isBigEndian = false;
    switch ( game.ProcessName.ToLower() ) {
        case "retroarch":
            long gpgxOffset = 0x01AF84;
            if ( game.Is64Bit() ) {
                gpgxOffset = 0x24A3D0;
            }
            baseAddress = modules.Where(m => m.ModuleName == "genesis_plus_gx_libretro.dll").First().BaseAddress;
            genOffset = gpgxOffset;
            break;
        case "gens":
            genOffset = 0x40F5C;
            break;
        case "fusion":
            genOffset = 0x2A52D4;
            isBigEndian = true;
            break;
        case "segagameroom":
            baseAddress = modules.Where(m => m.ModuleName == "GenesisEmuWrapper.dll").First().BaseAddress;
            genOffset = 0xB677E8;
            break;
        case "segagenesisclassics":
            genOffset = 0x71704;
            break;

    }
    memoryOffset = memory.ReadValue<int>(IntPtr.Add(baseAddress, (int)genOffset) );

    vars.watchers = new MemoryWatcherList
    {
        new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xEE4E ) { Name = "level" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEE4E : 0xEE4F ) ) { Name = "zone" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEE4F : 0xEE4E ) ) { Name = "act" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + 0xFFFC ) { Name = "reset" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xF600 : 0xF601 ) ) { Name = "trigger" },
        new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xF7D2 ) { Name = "timebonus" },
        new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xFE28 ) { Name = "scoretally" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFF09 : 0xFF08 ) ) { Name = "chara" },
        new MemoryWatcher<ulong>( (IntPtr)memoryOffset + 0xFC00) { Name = "dez2end" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xB1E5 : 0xB1E4 ) ) { Name = "ddzboss" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xB279 : 0xB278 ) ) { Name = "sszboss" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEEE4 : 0xEEE5 ) ) { Name = "delactive" },

        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEF4B : 0xEF4A ) ) { Name = "savefile" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFDEB : 0xFDEA ) ) { Name = "savefilezone" },
        new MemoryWatcher<ushort>((IntPtr)memoryOffset + ( isBigEndian ? 0xF648 : 0xF647 ) ) { Name = "waterlevel" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFE25 : 0xFE24 ) ) { Name = "centiseconds" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFE48 : 0xFE49 ) ) { Name = "inspecialstage" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + 0xFFB0 ) { Name = "chaosemeralds" },
        new MemoryWatcher<byte>(  (IntPtr)memoryOffset + 0xFFB1 ) { Name = "superemeralds" },
        /* $FFA6-$FFA9  Level number in Blue Sphere  */
        /* $FFB0 	Number of chaos emeralds  */
        /* $FFB1 	Number of super emeralds  */
        /* $FFB2-$FFB8 	Array of finished special stages. Each byte represents one stage:

            0 - special stage not completed
            1 - chaos emerald collected
            2 - super emerald present but grayed
            3 - super emerald present and activated 
        */
    };
    vars.isBigEndian = isBigEndian;
    string gamename = memory.ReadString(IntPtr.Add((IntPtr)memoryOffset, (int)0xFFFC ),4);
    

    switch (gamename) {
        case "SM&K": // Big-E
        case "MSK&": // Little-E
            vars.gameshortname = "S3K";
            vars.DebugOutput("S3K Loaded");
            break;
        default:
            throw new NullReferenceException (String.Format("Game {0} not supported.", gamename ));
    }

    
}

update
{
    // Stores the curent phase the timer is in, so we can use the old one on the next frame.
    vars.watchers.UpdateAll(game);
    current.timerPhase = timer.CurrentPhase;

    if ( ( vars.watchers["chaosemeralds"].Current + vars.watchers["superemeralds"].Current ) > ( vars.watchers["chaosemeralds"].Old + vars.watchers["superemeralds"].Old ) ) {
        vars.gotEmerald = true;
        vars.emeraldcount = vars.watchers["chaosemeralds"].Current + vars.watchers["superemeralds"].Current;
    }
    // Water Level is 16 for levels without water, and another value for those with
    // it is always 0 after a reset upto and including the save select menu
    // centiseconds is reset to 0 upon accessing the save select menu as well, and starts as soon as the game starts
    // we use old.centiseconds to prevent flukes of them being 0.
    current.inMenu = ( vars.watchers["waterlevel"].Current == 0 && vars.watchers["centiseconds"].Current == 0 && vars.watchers["centiseconds"].Old == 0 );
    current.scoretally = vars.watchers["scoretally"].Current;
    current.timebonus = vars.watchers["timebonus"].Current;
    if ( vars.isBigEndian ) {
        current.scoretally = vars.SwapEndianness(vars.watchers["scoretally"].Current);
        current.timebonus  = vars.SwapEndianness(vars.watchers["timebonus"].Current);
    }
    

    //vars.DebugOutputExpando(current);
    if(((IDictionary<String, object>)old).ContainsKey("timerPhase")) {
        if ((old.timerPhase != current.timerPhase && old.timerPhase != TimerPhase.Paused) && current.timerPhase == TimerPhase.Running)
        //pressed start run or autostarted run
        {
            vars.DebugOutput("run start detected");
            
            vars.nextzone = 0;
            vars.nextact = 1;
            vars.dez2split = false;
            vars.ddzsplit = false;
            vars.sszsplit = false;
            vars.bonus = false;
            vars.savefile = vars.watchers["savefile"].Current;
            vars.skipsAct1Split = !settings["actsplit"];
            vars.specialstagetimer.Reset();
            vars.emeraldcount = 0;
            vars.gotEmerald  = false;
            vars.chaoscatchall = false;
            vars.chaossplits = 0;
        }
    }
    if ( vars.gotEmerald ) {
        vars.DebugOutput(String.Format("Got Emerald: Chaos: {0} Super: {0}", vars.watchers["chaosemeralds"].Current, vars.watchers["superemeralds"].Current));
    }
}

start
{
    if (vars.watchers["trigger"].Current == 0x8C && vars.watchers["act"].Current == 0 && vars.watchers["zone"].Current == 0)
    {
        
        return true;
    }
}

reset
{
    // detecting memory checksum at end of RAM area being 0 - only changes if ROM is reloaded (Hard Reset)
    // or if "DEL" is selected from the save file select menu.
    if ( 
        ( settings["hard_reset"] && vars.watchers["reset"].Current == 0 && vars.watchers["reset"].Old != 0 ) || 
        ( current.inMenu == true
            && ( 
                ( vars.watchers["savefile"].Current == 9 && vars.watchers["delactive"].Current == 0xFF && vars.watchers["delactive"].Old == 0 ) ||
                ( 
                    vars.watchers["savefile"].Current == vars.savefile && 
                    (vars.nextact + vars.nextzone) <= 1 && 
                    vars.watchers["savefilezone"].Old == 255 && 
                    vars.watchers["savefilezone"].Current == 0 )
            )
        ) 
    ) {
        return true;
    }
}

split
{
    bool split = false;
    if ( vars.watchers["inspecialstage"].Old == 1 && vars.watchers["inspecialstage"].Current == 0 ) {
        vars.chaossplits++;
        if ( vars.gotEmerald ) {
            if ( vars.emeraldcount == 7 ) {
                vars.chaoscatchall = true;
            }
            vars.gotEmerald = false;
            if ( vars.chaossplits <= 7 ) {
                return true;
            }
        } else {
            if ( vars.chaossplits <= 7 ) {
                vars.timerModel.SkipSplit();
            }
        }
    }
    if ( vars.chaoscatchall ) {
        vars.chaoscatchall = false;
        return true;
    }   
}

isLoading
{
    return ( vars.watchers["inspecialstage"].Current == 0 );
}


gameTime
{
    /* Ready for supporting S1 and S2, 
    so for S3K we just return what the GameTime currently is */
    double currentElapsedTime = timer.CurrentTime.GameTime.Value.TotalMilliseconds;
    /* if ( vars.addspecialstagetime ) {
        vars.addspecialstagetime = false;
        currentElapsedTime += vars.specialstagetimer.ElapsedMilliseconds;
        vars.specialstagetimer.Reset();
        vars.specialstagetimeadded = true;
    }*/
    return TimeSpan.FromMilliseconds(currentElapsedTime);
}