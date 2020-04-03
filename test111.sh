#!/bin/bash

#fetching the module name..........

mod1=$(egrep -o '\<module\> *([a-Z0=9]+)' $1 | sed 's/module *//g')

#.....................


sed -r ':x;${s/\n/ /g};N;bx'  $1  | sed -r -e   's/\(//g' -e 's/\)//g'  | sed  -r  -e  's/(.);/\1 ;/g'    -e 's/(\]) *([a-Z]*)/\1\2/g' -e  's/ *, */,/g' -e 's/reg//g' -e 's/logic//g' -e 's/wire//g'  >  temp_file2


#.........../////....feching the input port..//////..................


fil=$(sed -r 's/ *input/\n input/g' temp_file2  | sed -r 's/(\[[0-9]:[0-9]\])([a-Z]+),([a-Z]+)/\1\2,\1\3/g')

IFS=$' \n ,'
p=0

for i in $ $fil;do

	if [[ $i =~ input  ]];then
		p=1
		continue

	fi

	if [[ $i =~  output ]] || [[ $i =~ ';' ]] ;then
		p=0
		continue

	elif [[ p -eq 1 ]];then

		#remove leading and trilling edge................

		ii=$(echo $i |sed -r -e  's/^ *//g' -e 's/ *$//g' )

		arr[k++]=$ii

		#............store clock and reset..................

		if [[ $ii =~ (clk|clock|CLOCK|CLK|Clk|Clock)[a-Z0-9_]* ]] ;then

			c=$ii
		fi

		if [[ $ii =~ (rst|reset|RST|RESET|Reset|Rst)[a-Z0-9_]* ]] ;then

			rt=$ii
		fi

		if [[ $ii =~ (valid|enable|VALID|ENABLE|Valid|Enable)[a-Z0-9_]* ]]  || [[ $ii =~ (EN|En|en)[0-9]* ]];then

			en=$ii
		fi
	fi
done
#.............///////////end of fetching input port///....................


#............//////////fetching the output port/////////...............

fil1=$(sed -r 's/ *output/\n output/g' temp_file2  |  sed -r 's/(\[[0-9]:[0-9]\])([a-Z]+),([a-Z]+)/\1\2,\1\3/g')
IFS=$' \n ,'
#cat temp_file1
q=0
for i in $fil1 ;do
	if [[ $i =~ output  ]];then
		q=1
		continue
	fi

	if [[ $i =~  input ]] || [[ $i =~ ';' ]] ;then
		q=0
		continue

	elif [[ q -eq 1 ]];then
		arr1[k++]=$i
		echo   output  $i  >> temp2
	fi
done

#...................////end of fetching output port/////.............



#......................///////creating class transaction////////...............

#....cheak file exist or not.............

if test -f "transaction.sv";then
	rm transaction.sv
fi

echo "class transaction;" >> transaction.sv

echo " //declaring the transaction items" >> transaction.sv

for i in "${arr[@]}";do

	if [[ $i == $c  ]] || [[ $i == $rt ]]  || [[ $i == $en  ]];then
		continue
	else
		echo "rand bit $i;" >> transaction.sv

	fi
done

for i in "${arr1[@]}";do

	echo "  bit $i;" >> transaction.sv
done

cat<<EOT>>transaction.sv

function void display(string name);
    \$display("-------------------------");
    \$display("- %s ",name);
    \$display("-------------------------");

EOT

for i in "${arr[@]}";do

	if [[ $i == $c  ]] || [[ $i == $rt ]]  || [[ $i == $en  ]];then
		continue
	else
		gg=$(echo $i | sed -r 's/\[.*\](.*)/\1/g')

		echo  "	\$display(\"- $gg = %0d\",$gg);" >> transaction.sv
	fi


done

for i in "${arr1[@]}";do
	gg1=$(echo $i | sed -r 's/\[.*\](.*)/\1/g')

	echo  "	\$display(\"- $gg1 = %0d\",$gg1);" >> transaction.sv
done

cat<<EOT>>transaction.sv

    \$display("-------------------------");
  endfunction
endclass

EOT

#.............end 0f transaction class..................


#...............//////creating of genarator class///////////.................

cat<<EOT>>generator.sv

class generator;

  rand transaction trans;

  //repeat count, to specify number of items to generate
  int  repeat_count;

  mailbox gen2driv;

  //event, to indicate the end of transaction generation
  event ended;

  //constructor
  function new(mailbox gen2driv); 
    this.gen2driv = gen2driv;
  endfunction

  //main task, generates(create and randomizes) the repeat_count number of transaction packets and puts into mailbox
  task main();
    repeat(repeat_count) begin
    trans = new();
    if( !trans.randomize() ) \$fatal("Gen:: trans randomization failed");
      trans.display("[ Generator ]");
      gen2driv.put(trans);
    end
    -> ended; //triggering indicatesthe end of generation
  endtask

endclass

EOT

#..................end of generator class..................


#.................////..creating of interface..///////.............

#....cheak file exist or not.............

if test -f "interface.sv";then
	rm interface.sv
fi


echo "interface intf(input logic $c,$rt);" >> interface.sv

echo   "//declaring the signals" >>interface.sv

  [[ ! -z $en  ]] && echo "logic $en" >> interface.sv

	for i in "${arr[@]}";do

		if [[ $i == $c  ]] || [[ $i == $rt ]]  || [[ $i == $en  ]];then
			continue
		else


			echo  " logic $i;" >> interface.sv
		fi


	done

	for i in "${arr1[@]}";do
		echo  "logic $i;" >> interface.sv
	done

	echo "endinterface" >> interface.sv






	
	
	
	
	
#..................end of interface.////..............


#...............////////////creating environment class////////............

#....cheak file exist or not.............

if test -f "environment.sv";then
	rm environment.sv
fi


cat<<EOT>>environment.sv
\`include "transaction.sv"
\`include "generator.sv"
\`include "driver.sv"
class environment;

  //generator and driver instance
  generator gen;
  driver    driv;

  //mailbox handle's
  mailbox gen2driv;

  //virtual interface
  virtual intf vif;

  //constructor
  function new(virtual intf vif);
    //get the interface from test
    this.vif = vif;

    //creating the mailbox (Same handle will be shared across generator and driver)
    gen2driv = new();

    //creating generator and driver
    gen  = new(gen2driv);
    driv = new(vif,gen2driv);
  endfunction

  //
  task pre_test();
    driv.reset();
  endtask

  taskwait(gen.repeat_count == driv.no_transactions);
  endtask

  //run task
  task run;
    pre_test();
    test();
    post_test();
    \$finish;
  endtask

endclass test();
    fork
    gen.main();
    driv.main();
    join_any
  endtask

  task post_test();
	wait(gen.ended.triggered);
	wait(mon.repeat_count == gen.repeat_count);
   endtask

	task run;
		pre_test;
		test;   
		post_test;
		\$finish;
	endtask

endclass

EOT

#.................end of environment class.................



#.....................................//////// Random Test ////////................................

#....cheak file exist or not.............

if test -f "randam_test.sv";then
	rm randam_test.sv
fi

cat << EOT > random_test.sv
\`include "environment.sv"
program test(intf in);

	environment env;

	initial begin
		env = new(in);
		env.gen.repeat_count = 5;
		env.mon.repeat_count = 0;
		env.run;
	end

endprogram

EOT
#...............................end of randam Test ................................"

#.........................//////creating  top_test_bench///////...............

#....cheak file exist or not.............

if test -f "top_test_bench.sv";then
        rm top_test_bench.sv
fi


cat<<EOT>>top_test_bench.sv

//including interfcae and testcase files
\`include "interface.sv"


module tbench_top;

\`include "random_test.sv"

  //clock and reset signal declaration
  bit $c;
  bit $rt;

  //clock generation
  always #5 $c = ~$c;

  //reset Generation
  initial begin
    $rt = 1;
    #5 $rt =0;
  end


  //creatinng instance of interface, inorder to connect DUT and testcase
  intf i_intf($c,$rt);

  //Testcase instance, interface handle is passed to test as an argument
  test t1(i_intf);


EOT



echo  "DUT $mod1 (" >>top_test_bench.sv

#..................
for i in "${arr[@]}";do
        g=$(echo $i | sed -r 's/\[.*\](.*)/\1/g')
        echo ".$g(i_intf.$g)," >> top_test_bench.sv
done

g11=$(echo "${#arr1[*]}")
for i in "${arr1[@]}";do

        g1=$(echo $i | sed -r 's/\[.*\](.*)/\1/g')
        g11=$g11-1

        echo -n  ".$g1(i_intf.$g1)" >> top_test_bench.sv
        if [[ $g11 -gt 0 ]];then

                echo "," >> top_test_bench.sv
        fi
done


echo  " );" >> top_test_bench.sv


cat<<EOT>>top_test_bench.sv

 //enabling the wave dump
  initial begin 
    \$dumpfile("dump.vcd"); \$dumpvars;
  end
endmodulenclude "random_test.sv" 

EOT


#.........................//////creating  top_test_bench///////...............

echo "hi"
