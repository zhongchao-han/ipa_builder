ipa_builder
===========

Automated iOS App Builder and Distributor (via TestFlight)

### Usage
`ipa_builder.sh [options] path (to xcodeproj)`

OPTIONS:

  -c     : Build configuration (**required**), examples: *adhoc*, *distrib*  
  -s     : Scheme to build (optional)  
  -t     : Target to build (optional)  
  
  -i     : Codesign identity (optional), example: *"iPhone Distribution: ..."*   
  -p     : Provisioning profile path (optional)  
  
  -n     : TestFlight release notes (optional)  
  -l     : TestFlight distribution lists (optional)  
  -d     : Put archived dSYM to the output directory ("yes"/"no") (optional)  
   
### Notes

   - Support for xcworkspaces is currently not implemented (because I don't use it). Although it can be added in the near future or feel free to make a contribution. ;)
   - If neither scheme nor target param is not specified — defaults will be used
   - If codesign and provisioning params are not specified — script will try to find and match them automatically
   - Don't forget to set TESTFLIGHT\_API\_TOKEN and TESTFLIGHT\_TEAM\_TOKEN vars before using TestFlight distribution!