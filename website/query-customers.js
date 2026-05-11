const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');

// Load .env.local
const envPath = path.join(__dirname, '.env.local');
const envContent = fs.readFileSync(envPath, 'utf8');
const env = {};
envContent.split('\n').forEach(line => {
  const [key, value] = line.split('=');
  if (key && value) {
    env[key.trim()] = value.trim();
  }
});

const supabase = createClient(
  env.NEXT_PUBLIC_SUPABASE_URL,
  env.NEXT_PUBLIC_SUPABASE_ANON_KEY
);

async function countByCustomerType() {
  try {
    const { data, error } = await supabase
      .schema('bps')
      .from('fnd_customers')
      .select('customer_type');

    if (error) {
      console.error('Error:', error);
      return;
    }

    // Count by customer_type
    const counts = {};
    data.forEach(row => {
      const type = row.customer_type || 'NULL';
      counts[type] = (counts[type] || 0) + 1;
    });

    console.log('\nRecords by Customer Type:');
    console.log('========================');
    Object.entries(counts)
      .sort((a, b) => b[1] - a[1])
      .forEach(([type, count]) => {
        console.log(`${type}: ${count}`);
      });
    console.log('========================');
    console.log(`Total: ${data.length}\n`);
  } catch (err) {
    console.error('Exception:', err.message);
  }
}

countByCustomerType();
