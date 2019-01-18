:: This script is used for flashing i.MX android images whit fastboot.

:: Do not output the command
@echo off

::---------------------------------------------------------------------------------
::Variables
::---------------------------------------------------------------------------------

:: For batch script, %0 is not script name in a so-called function, so save the script name here
set script_first_argument=%0
:: For users execute this script in powershell, clear the quation marks first.
set script_first_argument=%script_first_argument:"=%
:: reserve last 13 characters, which is the lenght of the name of this script file.
set script_name=%script_first_argument:~-25%

set soc_name=
set device_character=
set /A card_size=0
set slot=
set bootimage=boot.img
set systemimage_file=system.img
set vendor_file=vendor.img
set partition_file=partition-table.img
set /A support_dtbo=0
set /A support_recovery=0
set /A support_dualslot=0
set /A support_m4_os=0
set boot_partition=boot
set recovery_partition=recovery
set system_partition=system
set vendor_partition=vendor
set vbmeta_partition=vbmeta
set dtbo_partition=dtbo
set m4_os_partition=m4_os
set /A flash_m4=0
set /A statisc=0
set /A erase=0
set image_directory=
set fastboot_tool=fastboot
set target_dev=emmc
set sdp=SDP
set /A uboot_env_start=0
set /A uboot_env_len=0
set board=
set imx7ulp_evk_m4_sf_start_byte=0
set imx7ulp_evk_m4_sf_length_byte=0x20000
set imx7ulp_stage_base_addr=0x60800000
set imx8qm_stage_base_addr=0x98000000
set bootloader_usbd_by_uuu=
set bootloader_flashed_to_board=
set yocto_image=
set /A error_level=0
set /A intervene=0
set /A support_dual_bootloader=0
set dual_bootloader_partition=


::---------------------------------------------------------------------------------
:: Parse command line, since there is no syntax like "switch case" in bat file, 
:: the way to process the command line is a bit redundant, still, it can work.
::---------------------------------------------------------------------------------
:: If no option provied when executing this script, show help message and exit.
if [%1] == [] (
    echo please provide more information with command script options
    call :help
    goto :eof
)

:parse_loop
if [%1] == [] goto :parse_end
if %1 == -h call :help & goto :eof
if %1 == -f set soc_name=%2& shift & shift & goto :parse_loop
if %1 == -c set /A card_size=%2& shift & shift & goto :parse_loop
if %1 == -d set device_character=%2& shift & shift & goto :parse_loop
if %1 == -a set slot=_a& shift & goto :parse_loop
if %1 == -b set slot=_b& shift & goto :parse_loop
if %1 == -m set /A flash_m4=1 & shift & goto :parse_loop
if %1 == -e set /A erase=1 & shift & goto :parse_loop
if %1 == -D set image_directory=%2& shift & shift & goto :parse_loop
if %1 == -t set target_dev=%2&shift &shift & goto :parse_loop
if %1 == -p set board=%2&shift &shift & goto :parse_loop
if %1 == -y set yocto_image=%2&shift &shift & goto :parse_loop
if %1 == -i set /A intervene=1 & shift & goto :parse_loop
echo an option you specified is not supported, please check it
call :help & set /A error_level=1 && goto :exit
:parse_end


:: If sdcard size is not correctly set, exit
if %card_size% neq 0 set /A statisc+=1
if %card_size% neq 7 set /A statisc+=1
if %card_size% neq 14 set /A statisc+=1
if %card_size% neq 28 set /A statisc+=1
if %statisc% == 4 echo card_size is not a legal value & set /A error_level=1 && goto :exit

if %card_size% gtr 0 set partition_file=partition-table-%card_size%GB.img

:: if directory is specified, and the last character is not backslash, add one backslash
if not [%image_directory%] == [] if not %image_directory:~-1% == \ (
    set image_directory=%image_directory%\
)

:: get device and board specific parameter, for now, this step can't make sure the soc_name is definitely correct
if not [%soc_name:imx8qm=%] == [%soc_name%] (
    set vid=0x1fc9& set pid=0x0129& set chip=MX8QM
    set uboot_env_start=0x2000& set uboot_env_len=0x10
    set emmc_num=0& set sd_num=1
    set board=mek
    goto :device_info_end
)
if not [%soc_name:imx8qxp=%] == [%soc_name%] (
    set vid=0x1fc9& set pid=0x012f& set chip=MX8QXP
    set uboot_env_start=0x2000& set uboot_env_len=0x10
    set emmc_num=0& set sd_num=1
    set board=mek
    goto :device_info_end
)
if not [%soc_name:imx8mq=%] == [%soc_name%] (
    set vid=0x1fc9& set pid=0x012b& set chip=MX8MQ
    set uboot_env_start=0x2000& set uboot_env_len=0x8
    set emmc_num=0& set sd_num=1
    if [%board%] == [] (
        set board=evk
    )
    goto :device_info_end
)
if not [%soc_name:imx8mm=%] == [%soc_name%] (
    set vid=0x1fc9& set pid=00x0134& set chip=MX8MM
    set uboot_env_start=0x2000& set uboot_env_len=0x8
    set emmc_num=1& set sd_num=0
    set board=evk
    goto :device_info_end
)
if not [%soc_name:imx7ulp=%] == [%soc_name%] (
    set vid=0x1fc9& set pid=0x0126& set chip=MX7ULP
    set uboot_env_start=0x700& set uboot_env_len=0x10
    set sd_num=0
    set board=evk
    if [%target_dev%] == [emmc] (
        call :target_dev_not_support
    )
    goto :device_info_end
)
if not [%soc_name:imx7d=%] == [%soc_name%] (
    set vid=0x15a2& set pid=0x0076& set chip=MX7D
    set uboot_env_start=0x700& set uboot_env_len=0x10
    set sd_num=0
    set board=sabresd
    if [%target_dev%] == [emmc] (
        call :target_dev_not_support
    )
    goto :device_info_end
)
if not [%soc_name:imx6sx=%] == [%soc_name%] (
    set vid=0x15a2& set pid=0x0071& set chip=MX6SX
    set uboot_env_start=0x700& set uboot_env_len=0x10
    set sd_num=2
    set board=sabresd
    if [%target_dev%] == [emmc] (
        call :target_dev_not_support
    )
    goto :device_info_end
)
if not [%soc_name:imx6dl=%] == [%soc_name%] (
    set vid=0x15a2& set pid=0x0061& set chip=MX6DL
    set uboot_env_start=0x700& set uboot_env_len=0x10
    set emmc_num=2& set sd_num=1
    call :board_info_test
    if [%target_dev%] == [emmc] (
        if [%board%] == [sabreauto] call :target_dev_not_support
    )
    goto :device_info_end
)
if not [%soc_name:imx6q=%] == [%soc_name%] (
    set vid=0x15a2& set pid=0x0054& set chip=MX6Q
    set uboot_env_start=0x700& set uboot_env_len=0x10
    set emmc_num=2& set sd_num=1
    call :board_info_test
    if [%target_dev%] == [emmc] (
        if [%board%] == [sabreauto] call :target_dev_not_support
    )
    goto :device_info_end
)
echo please check whether the soc_name you specified is correct
call :help & set /A error_level=1 && goto :exit
:device_info_end

:: set target_num based on target_dev
if [%target_dev%] == [emmc] (
    set target_num=%emmc_num%
)else (
    set target_num=%sd_num%
)

:: set sdp command name based on soc_name
if not [%soc_name:imx8q=%] == [%soc_name%] (
    set sdp=SDPS
)

:: find the names of the bootloader used by uuu and flashed to board
if [%device_character%] == [ldo] goto :the_name_of_bootloader_with_device_character
if [%device_character%] == [epdc] goto :the_name_of_bootloader_with_device_character
if [%device_character%] == [ddr4] goto :the_name_of_bootloader_with_device_character
goto :the_name_of_bootloader_without_device_character
:the_name_of_bootloader_with_device_character
set bootloader_usbd_by_uuu=u-boot-%soc_name%-%device_character%-%board%-uuu.imx
set bootloader_flashed_to_board=u-boot-%soc_name%-%device_character%.imx
goto :the_name_of_bootloader_end
:the_name_of_bootloader_without_device_character
set bootloader_usbd_by_uuu=u-boot-%soc_name%-%board%-uuu.imx
set bootloader_flashed_to_board=u-boot-%soc_name%.imx
goto :the_name_of_bootloader_end
:the_name_of_bootloader_end

::---------------------------------------------------------------------------------
:: Invoke function to flash android images
::---------------------------------------------------------------------------------
call :uuu_load_uboot

call :flash_android

if %erase% == 1 (
    %fastboot_tool% erase userdata || set /A error_level=1 && goto :exit
    %fastboot_tool% erase misc || set /A error_level=1 && goto :exit
    if %soc_name:imx8=% == %soc_name% (
        %fastboot_tool% erase cache || set /A error_level=1 && goto :exit
    )
)

:: make sure device is locked for boards don't use tee
%fastboot_tool% erase presistdata || set /A error_level=1 && goto :exit
%fastboot_tool% erase fbmisc || set /A error_level=1 && goto :exit

if not [%slot%] == [] if %support_dualslot% == 1 (
    %fastboot_tool% set_active %slot:~-1% || set /A error_level=1 && goto :exit
)

:: flash yocto image along with mek_8qm auto xen images
if not [%yocto_image%] == [] (
    if [%soc_name%] == [imx8qm] (
        if [%device_character%] == [xen] (
            setlocal enabledelayedexpansion
            set target_num=%sd_num%
            uuu FB: ucmd setenv fastboot_dev mmc
            uuu FB: ucmd setenv mmcdev !target_num!
            uuu FB: ucmd mmc dev !target_num!
            :: flash the yocto image to "all" partition of SD card
            uuu "FB[-t 600000]:" flash -raw2sparse all %yocto_image%
            :: replace uboot from yocto team with the one from android team
            %fastboot_tool% flash bootloader0 %image_directory%u-boot-imx8qm-xen-dom0.imx

            :: write the xen uboot from android team to FAT on SD card
            set xen_uboot_name=u-boot-%soc_name%-%device_character%.imx
            for /f "usebackq" %%A in ('%image_directory%!xen_uboot_name!') do set xen_uboot_size_dec=%%~zA
            call :dec_to_hex !xen_uboot_size_dec! xen_uboot_size_hex
            echo xen_uboot_name is !xen_uboot_name!
            echo xen_uboot_size_dec !xen_uboot_size_dec!
            echo xen_uboot_size_hex !xen_uboot_size_hex!
            %fastboot_tool% stage %image_directory%!xen_uboot_name!
            echo uuu FB: ucmd fatwrite mmc %sd_num% %imx8qm_stage_base_addr% !xen_uboot_name! 0x!xen_uboot_size_hex!
            uuu FB: ucmd fatwrite mmc %sd_num% %imx8qm_stage_base_addr% !xen_uboot_name! 0x!xen_uboot_size_hex!
        )
    ) else (
        echo -y option only applies for imx8qm xen images
        call :help & exit set /A error_level=1 && goto :exit
    )
)

echo #######ALL IMAGE FILES FLASHED#######


::---------------------------------------------------------------------------------
:: The execution will end.
::---------------------------------------------------------------------------------
goto :eof


::----------------------------------------------------------------------------------
:: Function definition
::----------------------------------------------------------------------------------

:help
echo.
echo Version: 1.2
echo Last change: add support for aiy_imx8mq platform.
echo currently suported platforms: sabresd_6dq, sabreauto_6q, sabresd_6sx, evk_7ulp, sabresd_7d
echo                               evk_8mm, evk_8mq, aiy_8mq, mek_8q, mek_8q_car
echo.
echo eg: uuu_imx_android_flash.bat -f imx8qm -a -e -D C:\Users\user_01\images\2018.11.10\imx_pi9.0\mek_8q\
echo eg: uuu_imx_android_flash.bat -f imx6qp -e -D C:\Users\user_01\images\2018.11.10\imx_pi9.0\sabresd_6dq\ -p sabresd
echo.
echo Usage: %script_name% ^<option^>
echo.
echo options:
echo  -h                displays this help message
echo  -f soc_name       flash android image file with soc_name
echo  -a                only flash image to slot_a
echo  -b                only flash image to slot_b
echo  -c card_size      optional setting: 7 / 14 / 28
echo                        If not set, use partition-table.img (default)
echo                        If set to  7, use partition-table-7GB.img  for  8GB SD card
echo                        If set to 14, use partition-table-14GB.img for 16GB SD card
echo                        If set to 28, use partition-table-28GB.img for 32GB SD card
echo                    Make sure the corresponding file exist for your platform
echo  -m                flash m4 image
echo  -d dev            flash dtbo, vbmeta and recovery image file with dev
echo                        If not set, use default dtbo, vbmeta and recovery image
echo  -e                erase user data after all image files being flashed
echo  -D directory      the directory of of images
echo                        No need to use this option if images are in current working directory
echo  -t target_dev     emmc or sd, emmc is default target_dev, make sure target device exist
echo  -p board          specify board for imx6dl, imx6q, imx6qp and imx8mq, since more than one platform we maintain Android on use these chips
echo                        For imx6dl, imx6q, imx6qp, this is mandatory, it can be followed with sabresd or sabreauto
echo                        For imx8mq, this option is only used internally. No need for other users to use this option
echo                        For other chips, this option doesn't work
echo -y yocto_image     flash yocto image together with imx8qm auto xen images. The parameter follows "-y" option should be a full path name
echo                    including the name of yocto sdcard image, this parameter could be a relative path or an absolute path
goto :eof

:target_dev_not_support
echo %soc_name%-%board% does not support %target_dev% as target device
echo change target device automatically
set target_dev=sd
goto :eof


:: test whether board info is specified for imx6dl, imx6q and imx6qp
:board_info_test
if [%board%] == [] (
    if [%device_character%] == [ldo] (
        set board=sabresd
    ) else (
        echo board info need to be specified for %soc_name% with -p option, it can be sabresd or sabreauto
        call :help & set /A error_level=1 && goto :exit
    )
)
goto :eof

:uuu_load_uboot
uuu CFG: %sdp%: -chip %chip% -vid %vid% -pid %pid%

uuu %sdp%: boot -f %image_directory%%bootloader_usbd_by_uuu% || set /A error_level=1 && goto :exit

if not [%soc_name:imx8m=%] == [%soc_name%] (
    uuu SDPU: delay 1000
    uuu SDPU: write -f %image_directory%%bootloader_usbd_by_uuu% -offset 0x57c00
    uuu SDPU: jump
)

uuu FB: ucmd setenv fastboot_dev mmc
uuu FB: ucmd setenv mmcdev %target_num%
uuu FB: ucmd mmc dev %target_num%

:: erase environment variables of uboot
if [%target_dev%] == [emmc] (
    uuu FB: ucmd mmc dev %target_num% 0 || set /A error_level=1 && goto :exit
)
uuu FB: ucmd mmc erase %uboot_env_start% %uboot_env_len%
if [%target_dev%] == [emmc] (
    uuu FB: ucmd mmc partconf %target_num% 1 1 1 || set /A error_level=1 && goto :exit
)

if %intervene% == 1 (
    set /A error_level=0 && goto :exit
)

goto :eof

:flash_partition
set partition_to_be_flashed=%1
:: if there is slot information, delete it.
set local_str=%1
set local_str=%local_str:_a=%
set local_str=%local_str:_b=%

set img_name=%local_str%-%soc_name%.img

if not [%partition_to_be_flashed:bootloader_=%] == [%partition_to_be_flashed%] (
    set img_name=%uboot_proper_to_be_flashed%
    goto :start_to_flash
)

if not [%partition_to_be_flashed:system=%] == [%partition_to_be_flashed%] (
    set img_name=%systemimage_file%
    goto :start_to_flash
)
if not [%partition_to_be_flashed:vendor=%] == [%partition_to_be_flashed%] (
    set img_name=%vendor_file%
    goto :start_to_flash
)
if not [%partition_to_be_flashed:m4_os=%] == [%partition_to_be_flashed%] (
    set img_name=%soc_name%_m4_demo.img
    goto :start_to_flash
)
if not [%partition_to_be_flashed:vbmeta=%] == [%partition_to_be_flashed%] if not [%device_character%] == [] (
    set img_name=%local_str%-%soc_name%-%device_character%.img
    goto :start_to_flash
)
if not [%partition_to_be_flashed:dtbo=%] == [%partition_to_be_flashed%] if not [%device_character%] == [] (
    set img_name=%local_str%-%soc_name%-%device_character%.img
    goto :start_to_flash
)
if not [%partition_to_be_flashed:recovery=%] == [%partition_to_be_flashed%] if not [%device_character%] == [] (
    set img_name=%local_str%-%soc_name%-%device_character%.img
    goto :start_to_flash
)
if not [%partition_to_be_flashed:bootloader=%] == [%partition_to_be_flashed%] (
    set img_name=%bootloader_flashed_to_board%
    goto :start_to_flash
)


if %support_dtbo% == 1 (
    if not [%partition_to_be_flashed:boot=%] == [%partition_to_be_flashed%] (
        set img_name=%bootimage%
        goto :start_to_flash
    )
)

if not [%partition_to_be_flashed:gpt=%] == [%partition_to_be_flashed%] (
    set img_name=%partition_file%
    goto :start_to_flash
)

:start_to_flash
echo flash the file of %img_name% to the partition of %partition_to_be_flashed%
%fastboot_tool% flash %1 %image_directory%%img_name% || set /A error_level=1 && goto :exit
goto :eof


:flash_userpartitions
if %support_dual_bootloader% == 1 call :flash_partition %dual_bootloader_partition%
if %support_dtbo% == 1 call :flash_partition %dtbo_partition%
if %support_recovery% == 1 call :flash_partition %recovery_partition%
call :flash_partition %boot_partition%
call :flash_partition %system_partition%
call :flash_partition %vendor_partition%
call :flash_partition %vbmeta_partition%
goto :eof


:flash_partition_name
set boot_partition=boot%1
set recovery_partition=recovery%1
set system_partition=system%1
set vendor_partition=vendor%1
set vbmeta_partition=vbmeta%1
set dtbo_partition=dtbo%1
if %support_dual_bootloader% == 1 set dual_bootloader_partition=bootloader%1
goto :eof

:flash_android
call :flash_partition gpt

:: force to load the gpt just flashed, since for imx6 and imx7, we use uboot from BSP team,
:: so partition table is not automatically loaded after gpt partition is flashed.
uuu FB: ucmd setenv fastboot_dev sata
uuu FB: ucmd setenv fastboot_dev mmc

%fastboot_tool% getvar all 2> fastboot_var.log || set /A error_level=1 && goto :exit

find "bootloader_a" fastboot_var.log > nul && set /A support_dual_bootloader=1

find "dtbo" fastboot_var.log > nul && set /A support_dtbo=1

find "recovery" fastboot_var.log > nul && set /A support_recovery=1

::use boot_b to check whether current gpt support a/b slot
find "boot_b" fastboot_var.log > nul && set /A support_dualslot=1

:: since imx7ulp uboot from bsp team is used for uuu, m4 os partiton for imx7ulp_evd doesn't exist here
find "m4_os" fastboot_var.log > nul && set /A support_m4_os=1

:: if dual bootloader is supported, the name of the bootloader flashed to the board need to be updated
if %support_dual_bootloader% == 1 (
    set bootloader_flashed_to_board=spl-%soc_name%.bin
    set uboot_proper_to_be_flashed=bootloader-%soc_name%.img
)

:: for xen mode, no need to flash bootloader
if not [%device_character%] == [xen] (
    if not %soc_name:imx8=% == %soc_name% (
        call :flash_partition bootloader0
    ) else (
        call :flash_partition bootloader
    )
)

if %support_dualslot% == 0 (
    if not [%slot%] == [] (
        echo ab slot feature not supported, the slot you specified will be ignored
        set slot=
    )
)

if %flash_m4% == 1 if %support_m4_os% == 1 call :flash_partition %m4_os_partition%

::since imx7ulp use uboot for uuu from BSP team, if m4 need to be flashed, flash it here.
if [%soc_name%] == [imx7ulp] (
    if [%flash_m4%] == [1] (
        :: download m4 image to sdram
        %fastboot_tool% stage %image_directory%%soc_name%_m4_demo.img

        uuu FB: ucmd sf probe
        echo uuu_version 1.1.81 > m4.lst
        echo CFG: %sdp%: -chip %chip% -vid %vid% -pid %pid% >> m4.lst
        echo FB[-t 30000]: ucmd sf erase %imx7ulp_evk_m4_sf_start_byte% %imx7ulp_evk_m4_sf_length_byte% >> m4.lst
        echo FB[-t 30000]: ucmd sf write %imx7ulp_stage_base_addr% %imx7ulp_evk_m4_sf_start_byte% %imx7ulp_evk_m4_sf_length_byte% >> m4.lst
        echo FB: done >> m4.lst
        :: write the image to spi nor-flash
        echo flash the file of imx7ulp_m4_demo.img to the partition of m4_os
        uuu m4.lst
        del m4.lst
    )
)


if [%slot%] == [] (
    if %support_dualslot% == 1 (
:: flash image to both a and b slot
        call :flash_partition_name _a
        call :flash_userpartitions

        call :flash_partition_name _b
        call :flash_userpartitions
    ) else (
        call :flash_partition_name
        call :flash_userpartitions
    )
)
if not [%slot%] == [] (
    call :flash_partition_name %slot%
    call :flash_userpartitions
)


del fastboot_var.log

goto :eof

:dec_to_hex
set base_num=0123456789abcdef
(for /f "usebackq" %%A in ('%1') do call :post_dec_to_hex %%A) > temp_hex.txt
set /P %2=<temp_hex.txt
del temp_hex.txt
goto :eof
:post_dec_to_hex
set dec=%1
set hex=
setlocal enabledelayedexpansion
:division_modular_loop
set /a mod = dec %% 16,dec /= 16
set hex=!base_num:~%mod%,1!!hex!
if not [!dec!] == [0] (
    goto :division_modular_loop
)
echo !hex!
goto :eof

:exit
exit
