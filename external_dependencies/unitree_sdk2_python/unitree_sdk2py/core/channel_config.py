import os

# Per-user log avoids permission errors when multiple users share /tmp/cdds.LOG
_CDDS_LOG = f"/tmp/cdds.{os.environ.get('USER', 'default')}.LOG"

ChannelConfigHasInterface = f'''<?xml version="1.0" encoding="UTF-8" ?>
    <CycloneDDS>
        <Domain Id="any">
            <General>
                <Interfaces>
                    <NetworkInterface name="$__IF_NAME__$" priority="default" multicast="default"/>
                </Interfaces>
            </General>
            <Tracing>
                <Verbosity>config</Verbosity>
            <OutputFile>{_CDDS_LOG}</OutputFile>
        </Tracing>
        </Domain>
    </CycloneDDS>'''

ChannelConfigAutoDetermine = '''<?xml version="1.0" encoding="UTF-8" ?>
    <CycloneDDS>
        <Domain Id="any">
            <General>
                <Interfaces>
                    <NetworkInterface autodetermine=\"true\" priority=\"default\" multicast=\"default\" />
                </Interfaces>
            </General>
        </Domain>
    </CycloneDDS>'''
