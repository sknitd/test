import java.io.BufferedWriter;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileWriter;
import java.io.IOException;
import java.io.Writer;
import java.util.Scanner;

public class BooksMenu {

	public static void main(String[] args) {
		Scanner sc= new Scanner(System.in);
		int choice=0;
		BooksMenu obj= new BooksMenu();
		System.out.println("\t  Library record");
		System.out.println("\t1.Add book information");
		System.out.println("\t2.Display Book Information");
		System.out.println("\t3.List of all books of the given Author");
		
		System.out.println("\t4.List the title of the specified book");
		System.out.println("\t5.List Count of all books in the library");
		System.out.println("\t6.List of books in the order of accession number");
		
		System.out.println("\tEnter choice-");
		choice= sc.nextInt();
		
		while(choice<1 || choice >6)
		{ System.out.println("\tEnter correct choice=");
		choice =sc.nextInt();
		}
		
		switch(choice) 
		{case 1:
			try {
				obj.addInfo();
			} catch (IOException e) {
				// TODO Auto-generated catch block
				e.printStackTrace();
			}
			break;
		case 2: obj.displayBI();
		break;
		case 3:obj.allBooksOfAuthor();
		break;
		case 4:
			obj.listTitle();
			break;
		case 5: obj.booksCount();
		break;
		case 6:
			obj.booksOrder();
			break;
			
			
		}
		
		
		
	}

	
	private void booksOrder() {
		// TODO Auto-generated method stub
		// TODO Auto-generated method stub
				File file= new File("booklist.txt");
			
				try {
					Scanner sc= new Scanner(file);
					int line=0;
					
					while(sc.hasNextLine())
					{
						String s= sc.nextLine();
						line++;
						//System.out.println(s);
					
					}
					String st[][]=new String[line][500];
					line=0;String str="";
					sc= new Scanner(file);
					while(sc.hasNextLine())
					{
						String s= sc.nextLine();s=s+"\t\t";
						if(line>=1)
						{
						//str=str+s+'\n';
							str=s.replace('\t', ',');
						
						st[line-1]=str.split(",,");
						//System.out.println(s.replace("\t\t", ","));
						}
						line++;
					
					}
					;
			long g[]=new long[line];
				int ord[]=new int[line];
				int f=0;
					String cg="";
					for(int i=0;i<line;i++){
						for( String c : st[i])
							{if(  c!=null )
							{
								//g[i]=new Integer(c);
							ord[i]=i;//System.out.println(g);
							cg=c;
							
							}}
					//if(g.contains(acc+""))
						//{System.out.println(g.substring(0, g.indexOf(acc+"")));  f=1;
						//}
					//else 
					//g="";
					f=1;
					//System.out.println(i);	}
					//System.out.println(cg.lastIndexOf(","));
					if(cg.contains(",")) 
					{System.out.println(cg.substring(cg.lastIndexOf(",")+1,cg.length()));
					g[i]=new Long(cg.substring(cg.lastIndexOf(",")+1,cg.length()));
					}
					else {System.out.println(cg);
					g[i]=new Long(cg);
					}
					for(long v:g) System.out.println(v);
					//if(f==0) System.out.println("not found");
					}
				} catch (FileNotFoundException e) {
					// TODO Auto-generated catch block
					e.printStackTrace();
				}
				catch(Exception e){}
		
	}


	private void booksCount() {
		// TODO Auto-generated method stub
		File file= new File("booklist.txt");
		try {
			Scanner sc= new Scanner(file);
			int line=0;
		
		
			while(sc.hasNextLine())
			{
				String s= sc.nextLine();
				line++;
				//System.out.println(s);
			
			}
			System.out.println("Total no of books="+(line-1));
	}
		catch(Exception e){}
	}


	private void listTitle() {
		// TODO Auto-generated method stub
		File file= new File("booklist.txt");
		try {
			Scanner sc= new Scanner(file);
			int line=0;
			System.out.println("Enter accession no. to see books in this library=");
			int acc= new Scanner(System.in).nextInt();
			while(sc.hasNextLine())
			{
				String s= sc.nextLine();
				line++;
				//System.out.println(s);
			
			}
			String st[][]=new String[line][500];
			line=0;String str="";
			sc= new Scanner(file);
			while(sc.hasNextLine())
			{
				String s= sc.nextLine();s=s+"\t\t";
				if(line>=1)
				{
				//str=str+s+'\n';
					str=s.replace('\t', ',');
				
				st[line-1]=str.split(",,");
				//System.out.println(s.replace("\t\t", ","));
				}
				line++;
			
			}
			;
		String g="";
		int f=0;
			
			for(int i=0;i<line;i++){
				for(String c : st[i])
					if(c!=null )
					{g=g+c.toLowerCase();//System.out.println(g);
					}
			if(g.contains(acc+""))
				{System.out.println(g.substring(0, g.indexOf(acc+"")));  f=1;
				}
			//else 
			g="";
				}
			if(f==0) System.out.println("not found");
		} catch (FileNotFoundException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
		

		
	}


	private void allBooksOfAuthor()  {
		// TODO Auto-generated method stub
		File file= new File("booklist.txt");
		try {
			Scanner sc= new Scanner(file);
			int line=0;
			System.out.println("Enter author name to see (his/her)'s books in this library=");
			String au= new Scanner(System.in).next();
			while(sc.hasNextLine())
			{
				String s= sc.nextLine();
				line++;
				//System.out.println(s);
			
			}
			String st[][]=new String[line][500];
			line=0;String str="";
			sc= new Scanner(file);
			while(sc.hasNextLine())
			{
				String s= sc.nextLine();s=s+"\t\t";
				if(line>=1)
				{
				//str=str+s+'\n';
					str=s.replace('\t', ',');
				
				st[line-1]=str.split(",,");
				//System.out.println(s.replace("\t\t", ","));
				}
				line++;
			
			}
			;
		String g="";
			int f=0;
			for(int i=0;i<line;i++){
				for(String c : st[i])
					if(c!=null )
					{g=g+c.toLowerCase();//System.out.println(g);
					}
			if(g.contains(au))
				{System.out.println(g.substring(0, g.indexOf(au))); f=1;
				}
			//else System.out.println("not found");
			g="";
				}
			if(f==0)System.out.println("not found");
			
		} catch (FileNotFoundException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
		
		
	}


	private void addInfo() throws IOException  {
		// TODO Auto-generated method stub
		File file= new File("booklist.txt");
		Scanner sc2= new Scanner(System.in);
		System.out.println("Enter book name=");
		String name=sc2.nextLine();
		System.out.println("Enter Author name=");
		String a=sc2.nextLine();
		System.out.println("Enter publisher name=");
		String pub=sc2.nextLine();
		
		System.out.println("Enter accession no.(int)=");
		int an=sc2.nextInt();
		int line=0;
	
		
		String str="";
		
		try {
			Scanner  sc= new Scanner(file);
			
			while(sc.hasNextLine())
			{
				String s= sc.nextLine();
				//System.out.println(s);
				str=str+s+'\n';
				line++;
			}
			if(str.contains(an+""))
				System.out.println("Book Already present");
			else{
			Writer wr= new FileWriter(file);
			BufferedWriter bw= new BufferedWriter(wr);
			System.out.println(str+line+".\t\t"+name+"\t\t"+a+"\t\t"+pub+"\t\t"+an);
			bw.write(str+line+".\t\t"+name+"\t\t"+a+"\t\t"+pub+"\t\t"+an);
			bw.close();
			}
		} catch (FileNotFoundException e) {
			// TODO Auto-generated catch block
			System.err.println(e);
			e.printStackTrace();
		} 
		
	}
	
	private void displayBI() {
		// TODO Auto-generated method stub
		File file= new File("booklist.txt");
		try {
			Scanner sc= new Scanner(file);
			while(sc.hasNextLine())
			{
				String s= sc.nextLine();
				System.out.println(s);
			
			
			}
		} catch (FileNotFoundException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
		
		
	}

}
