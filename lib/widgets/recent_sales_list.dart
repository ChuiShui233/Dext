import 'package:flutter/material.dart';

class RecentSalesList extends StatelessWidget {
  const RecentSalesList({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Sales',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'You made 265 sales this month.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // 销售记录列表
          _buildSalesItem('OM', 'Olivia Martin', 'olivia.martin@email.com', '+\$1,999.00'),
          const SizedBox(height: 16),
          _buildSalesItem('JL', 'Jackson Lee', 'jackson.lee@email.com', '+\$39.00'),
          const SizedBox(height: 16),
          _buildSalesItem('IN', 'Isabella Nguyen', 'isabella.nguyen@email.com', '+\$299.00'),
          const SizedBox(height: 16),
          _buildSalesItem('WK', 'William Kim', 'will@email.com', '+\$99.00'),
          const SizedBox(height: 16),
          _buildSalesItem('SD', 'Sofia Davis', 'sofia.davis@email.com', '+\$39.00'),
        ],
      ),
    );
  }

  Widget _buildSalesItem(String initials, String name, String email, String amount) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.grey[200],
          child: Text(
            initials,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              Text(
                email,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Text(
          amount,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
