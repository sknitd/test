import java.io.BufferedReader;

import java.io.FileReader;
import java.io.IOException;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.hssf.usermodel.HSSFCell;
import org.apache.poi.hssf.usermodel.HSSFRow;
import org.apache.poi.hssf.usermodel.HSSFSheet;
import org.apache.poi.hssf.usermodel.HSSFWorkbook;

 


public class ReadFileExample1 {

	private static final String FILENAME = "/home/osgdev/Desktop/exp_18_40374_1.1";

	public static void main(String[] args) {

		BufferedReader br = null,br1=null;
		FileReader fr = null,fr1=null;
		String st2[][] = null;
int ctr=0;
		try {

			//br = new BufferedReader(new FileReader(FILENAME));
			fr = new FileReader(FILENAME);
			br = new BufferedReader(fr);

			String sCurrentLine,s1,s="";

			while ((sCurrentLine = br.readLine()) != null) {
				//System.out.println("");
				//s=s+sCurrentLine+'\n';
				++ctr;
				//s=s+sCurrentLine+'\n';
			}
		
			System.out.println("ctr="+ctr);
			//System.out.println(s);
			String[] str=new String[ctr];
			ctr=0;str[0]="dfh";
			//System.out.println(str[0]);
			fr1 = new FileReader(FILENAME);
			br1 = new BufferedReader(fr1);
			while ((s1 = br1.readLine()) != null) {
				//System.out.println("11");
				s=s+s1;
				str[ctr]=s;
				s="";
				//System.out.println(sCurrentLine);
				ctr++;
				//s=s+sCurrentLine+'\n';
			}
			String st[]=str[1].split(",");
			String st1[] = null;
			 st2=new String[ctr][500];
			ctr=0;
			for(String c:str)
			{
				st1=c.split(",");
				st2[ctr++]=st1;
			}
			try {
				//System.out.println(st2[0][1]);
			} catch (Exception e) {
				// TODO Auto-generated catch block
				System.out.println("null");
			}
			

		} catch (IOException e) {

			e.printStackTrace();

		} finally {

			try {

				if (br != null)
					br.close();

				if (fr != null)
					fr.close();
				if (br1 != null)
					br.close();

				if (fr1 != null)
					fr.close();


			} catch (IOException ex) {

				ex.printStackTrace();

			}

		}
		
		HSSFWorkbook workbook = new HSSFWorkbook();
    	HSSFSheet sheet = workbook.createSheet("Sample sheet"); 
    	  ArrayList<String> list;
    	  Map<Integer,ArrayList<String>> data = new HashMap<Integer,ArrayList<String>>();
    	//list.add("hello");
    	//list.add("pagal");
    	  
    	//Map<String, Object[]> data = new HashMap<String, Object[]>();
	//	data.put("1", new Object[] {"Emp No.", "Name", "Salary"});
		//data.put("1", list);
    	//System.out.println(ctr);
		for(int g=0;g<ctr;g++)
		{  list=new ArrayList<String>();
		for(String c: st2[g])
			{System.out.println(c);
			list.add(c);
			}
		data.put(g, list);
		System.out.println("sdgd---"+list);
		System.out.println("iugijgiggg----"+data.get(0));
		//list.removeAll(list);
		//list.clear();
		}
		System.out.println("----->."+data.get(2));
		
		//{
			//data.put("2", new Object[] {st2[0][0]});
			//System.out.println(c);
		//}
		//data.put("2", new Object[] {1d, "John", 1500000d});
		//data.put("3", new Object[] {2d, "Sam", 800000d,50000d});
		//data.put("4", new Object[] {5d, "Dean", 700000d});
		
		Set<Integer> keyset = data.keySet();
		System.out.println(keyset);
		int rownum = 0;
		for (int key : keyset) {
			HSSFRow row =  sheet.createRow(rownum++);
			System.out.println(rownum);
			ArrayList<String> objArr = data.get(key);
			System.out.println(data.get((rownum-1)));
			//for(String c:objArr)
			//System.out.println(c);
			int cellnum = 0;
			for (String obj : objArr) {
				HSSFCell cell = row.createCell( (short) cellnum++);
				if(obj instanceof String) 
					cell.setCellValue(obj);
				/*else if(obj instanceof Boolean)
					cell.setCellValue((Boolean)obj);
				else if(obj instanceof String)
					cell.setCellValue((String)obj);
				else if(obj instanceof Double)
					cell.setCellValue((Double)obj);*/
			}
		}
		
		try {
			FileOutputStream out = 
					new FileOutputStream(new File("/home/osgdev/Desktop/new.xls"));
			workbook.write(out);
			out.close();
			System.out.println("Excel written successfully..");
			
		} catch (FileNotFoundException e) {
			e.printStackTrace();
		} catch (IOException e) {
			e.printStackTrace();
		}
    
    
    
    

		
		
		
		

	}//psvm end

}//class end
