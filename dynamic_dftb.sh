#!/bin/sh
#-----------------------------------------------#
#						#
#	bash dynamic_dftb.sh input.xyz		#
#						#	
#	it produces cuts/directory with 	#
#	the 10 most stable configuration	#
#	 of the dftb+ trajectory 		#
#						#
#-----------------------------------------------#

#links to binaries
dftb=/opt/dftbplus-19.1.x86_64-linux/bin/dftb+
dftb_input=/home/tutti/srusso/script/dinamica_MM/dftb/dftb_in.hsd
atomi=("H" "C" "N" "O" "F" "S")
filename=$(echo $1 | awk -F '.' '{print $1}')
numero_atomi=$(cat $1 | awk 'NR==1{print $1}' |xargs  echo "2+"| bc -l)

cp $dftb_input dftb_in.hsd_BAK

if [ -z "$2" ];
	then
		echo "Carica Totale" 0
		sed -i "s/CARICA_TOTALE/0/g" dftb_in.hsd_BAK
	else
		echo "Carica Totale" $2
                sed -i "s/CARICA_TOTALE/$2/g" dftb_in.hsd_BAK
	fi	

for i in ${atomi[@]};
do
if cat $1 | grep -q $i;
	then
                sed -i "s/PUPPA_$i/ /g" dftb_in.hsd_BAK
       	else
         	sed -i "s/PUPPA_$i/#/g" dftb_in.hsd_BAK
	fi
done


#---------------------------------------------#
# create dftb_in.hsd from dftb_input template #
#---------------------------------------------#

sed "1s/^/Driver = ConjugateGradient {\n  MovedAtoms = 1:-1\n  MaxForceComponent = 1.0e-3\n MaxSteps = 1000\n OutputPrefix = \"output\"\n}\n/" dftb_in.hsd_BAK > dftb_in.hsd
sed -i "1s/^/Geometry = GenFormat {\n<<<\"$filename.gen\"\n}\n\n/ " dftb_in.hsd

echo "########### Conversione XYZ -> GEN ##############"
xyz2gen $1


#-----------------------
echo "########### Minimizzazione Iniziale #############"
$dftb |tee tmp.txt| grep Geometry >> /dev/tty
if cat tmp.txt | grep -q "Geometry converged";
	then
		rm tmp.txt band.out  charges.bin  detailed.out  dftb_in.hsd dftb_pin.hsd output.xyz $filename.gen    #se procedura va liscia cancella il file temporaneo
		mv output.gen $filename.gen
	else 
		#se invece va male blocca tutto e scirve sul terminale
                echo  "#################### ERRORE #######################"
                echo  "#                                                 #"
                echo  "#   PROBLEMA NELLA MINIMIZE CONTROLLARE log1.txt  #"
                echo  "#                                                 #"
                echo  "###################################################"
		mv tmp.txt log1.txt
		exit 1
fi
#
#
#----------------------
#inizio della dinamica
echo "################ Inizio Dinamica ################"
#
#dinamica sono 50000 frame con 350kelvin, 1.0 e 0.1 sono il time step della dinamica
#
#bisogna creare il dftb_in.hsd
sed "1s/^/Driver = VelocityVerlet    {\n   MovedAtoms = 1:-1\n  OutputPrefix = \"trajec\" \n  Steps = 2000\n  Timestep [fs] = 0.5\n  KeepStationary = yes\n  MDRestartFrequency = 200\n  Thermostat = Berendsen {\n     temperature [kelvin] = 320 \n     Timescale [fs] = 1 }\n }\n/" dftb_in.hsd_BAK > dftb_in.hsd
sed -i "1s/^/Geometry = GenFormat {\n<<<\"$filename.gen\"\n}\n\n/ " dftb_in.hsd




$dftb |tee tmp.txt
if cat tmp.txt | grep -q "Geometry step: 2000";
	then
		rm tmp.txt band.out  charges.bin  detailed.out  dftb_in.hsd dftb_pin.hsd  hys_neg.gen md.out trajec.gen
	else
		echo  "#################### ERRORE #######################"
		echo  "#                                                 #"
		echo  "#   PROBLEMA NELLA DINAMICA CONTROLLARE din.log   #"
		echo  "#                                                 #"
		echo  "###################################################"
		mv tmp.txt din.log
		exit 1
fi

#una volta terminata la dinamica, crea una cartella /cuts
mkdir cuts
cd cuts
#
#dentro ci infila i 100 frame della dinamica
split ../trajec.xyz -l $numero_atomi cutt


#inizia poi un ciclo in cui minimizza tutti i frame
echo "############## Minimizzazione Frame ##############"


#
#
for i in *;
do
#trasformazone
xyz2gen $i
#crea dftb_in
sed "1s/^/Driver = ConjugateGradient {\n  MovedAtoms = 1:-1\n  MaxForceComponent = 5.0e-3\n MaxSteps = 500\n OutputPrefix = \"output\"\n}\n/" ../dftb_in.hsd_BAK > dftb_in.hsd
sed -i "1s/^/Geometry = GenFormat {\n<<<\"$i.gen\"\n}\n\n/ " dftb_in.hsd
$dftb |tee tmp.txt| grep "Geometry step" >> /dev/tty
	if cat tmp.txt | grep -q "Geometry converged"; 
		then
			echo $i "ok"
			rm $i band.out  charges.bin  detailed.out  dftb_in.hsd dftb_pin.hsd $i.gen output.gen
			mv output.xyz $i.xyz
			cat tmp.txt | grep "Total Energy" | awk -v x=$i '{print x"   "$3}' | tac | awk 'NR==1{print}' >> energy.txt
			rm tmp.txt
		else
			echo $i "########### ERROR ##########"
			echo $i "ERROR" >> ../log.txt
			mv tmp.txt $i.log 
	fi
done


echo "############### Calcolo Energia ###############"
cat energy.txt | sort -k2 -n | tee tmp.txt
rm energy.txt
mv tmp.txt energy.txt

#Copio il più stabile fuori dalla cartella
cat energy.txt | awk 'NR==1{print $1".xyz"}' | xargs -I '{}' mv '{}' ../

cd ..
rm dftb_in.hsd_BAK
rm *gen

echo "############ Programma Terminato Normalmente ############"
