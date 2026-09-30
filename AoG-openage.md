Mansa Musa: Empire of Gold strategy game using the openage engine, leveraging its modding capabilities and Python integration to create a historically rich, resource-driven experience:

---

### **1. Core Concept**
- **Genre**: Historical Real-Time Strategy (RTS) with economic/empire-building focus.
- **Setting**: 14th-century West Africa, spanning the Mali Empire’s territories (Timbuktu, Gao, Niani) and Mansa Musa’s legendary pilgrimage to Mecca.
- **Unique Hook**: Balance gold wealth management, Islamic scholarship, and trans-Saharan trade while avoiding destabilizing inflation from excessive spending.

---

### **2. Key Features**
#### **A. Economy & Trade**
- **Dynamic Gold Mechanics**:  
  - Mine gold deposits ([nyan](nyan)) to build wealth, but oversupply devalues gold regionally, affecting trade deals.  
  - Use gold to fund pilgrimages, construct mosques (e.g., Sankore Madrasah), or bribe rivals.
- **Caravan System**:  
  - Deploy camel caravans with customizable routes (Python scripting) to trade salt, gold, and manuscripts.  
  - Risks: Bandit raids, sandstorms (procedural events).

#### **B. Pilgrimage Campaign**
- **Pilgrimage to Mecca**:  
  - A multi-stage mission where spending gold in Cairo/Mecca boosts diplomatic reputation but risks economic collapse at home.  
  - Scripted events (Qt6 GUI): Meet scholars, negotiate with Mamluk sultans, manage entourage needs.

#### **C. Cultural Influence**
- **Scholars & Architecture**:  
  - Recruit scholars (unique unit) to spread Maliki jurisprudence, unlocking tech bonuses.  
  - Construct iconic landmarks (Great Mosque of Djenné) to increase cultural "soft power."

---

### **3. Technology Stack (Using openage)**
| Component              | Implementation                                                                 |
|-------------------------|-------------------------------------------------------------------------------|
| **Core Engine**         | C++20 for pathfinding (caravans), combat (Malian military vs. Tuareg raiders) |
| **Modding**             | `nyan` files to define civilizations (Mali, Songhai, Ghana), units, resources|
| **Scripting**           | Python3 API for:<br>- Random events (droughts, trade disputes)<br>- AI behavior (rival kingdoms) |
| **UI/UX**               | Qt6 for immersive menus with Arabic calligraphy and Sahelian art styles       |
| **Multiplayer**         | Matchmaking for competitive trade wars or cooperative caravan defense        |

---

### **4. Modding Plan**
1. **Civilization Design**:  
   - **Mali**: Bonuses to gold income and scholar efficiency.  
   - **Egypt (Mamluk)**: Strong military but gold-dependent.  
   - **Songhai**: Late-game powerhouse with cavalry.  
   ```nyan
   // Example nyan definition for Mali
   Civilization("Mali") {
     attributes: {
       gold_income_multiplier: 1.5,
       scholar_conversion_rate: 0.8
     }
   }
   ```

2. **Python Scripts**:  
   - Simulate inflation: `gold_value = base_value / (total_gold_in_circulation * 0.01)`  
   - Caravan route generator with risk-reward calculations.

---

### **5. Challenges & Solutions**
- **Historical Accuracy vs. Gameplay**:  
  Use openage’s mod tools to toggle between "Historical Mode" (realistic resource scarcity) and "Sandbox Mode" (unlimited gold).  
- **Performance**:  
  Optimize gold calculations with Cython-wrapped C++ modules.

---

### **Next Steps**
1. Prototype a single campaign mission (Timbuktu trade hub construction).  
2. Recruit artists for unit designs (Malian warriors, scholars in hijabs).  
3. Test multiplayer balance with openage’s matchmaking.  

Would you like to prioritize a specific feature or dive deeper into the modding workflow?
